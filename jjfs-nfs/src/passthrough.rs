// Pass-through filesystem that mirrors a real directory
// Based on nfsserve demo but reads/writes to actual filesystem

use async_trait::async_trait;
use nfsserve::{
    nfs::{
        fattr3, fileid3, filename3, ftype3, nfspath3, nfsstat3, nfsstring, nfstime3, sattr3,
        specdata3,
    },
    vfs::{DirEntry, NFSFileSystem, ReadDirResult, VFSCapabilities},
};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::SystemTime;
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[derive(Debug)]
struct PathEntry {
    id: fileid3,
    path: PathBuf,
}

pub struct PassthroughFS {
    root: PathBuf,
    next_id: Mutex<u64>,
    id_to_path: Mutex<HashMap<fileid3, PathBuf>>,
    path_to_id: Mutex<HashMap<PathBuf, fileid3>>,
}

impl PassthroughFS {
    pub fn new(root: PathBuf) -> Self {
        let mut id_to_path = HashMap::new();
        let mut path_to_id = HashMap::new();

        // Root is always ID 1
        id_to_path.insert(1, root.clone());
        path_to_id.insert(root.clone(), 1);

        Self {
            root,
            next_id: Mutex::new(2), // Start at 2, root is 1
            id_to_path: Mutex::new(id_to_path),
            path_to_id: Mutex::new(path_to_id),
        }
    }

    fn get_or_create_id(&self, path: &Path) -> fileid3 {
        let mut path_to_id = self.path_to_id.lock().unwrap();
        let mut id_to_path = self.id_to_path.lock().unwrap();

        if let Some(&id) = path_to_id.get(path) {
            return id;
        }

        let mut next_id = self.next_id.lock().unwrap();
        let id = *next_id;
        *next_id += 1;

        id_to_path.insert(id, path.to_path_buf());
        path_to_id.insert(path.to_path_buf(), id);

        id
    }

    fn get_path(&self, id: fileid3) -> Option<PathBuf> {
        let id_to_path = self.id_to_path.lock().unwrap();
        id_to_path.get(&id).cloned()
    }

    async fn path_to_fattr(&self, path: &Path, id: fileid3) -> Result<fattr3, nfsstat3> {
        let metadata = fs::metadata(path).await.map_err(|_| nfsstat3::NFS3ERR_IO)?;

        let ftype = if metadata.is_dir() {
            ftype3::NF3DIR
        } else if metadata.is_symlink() {
            ftype3::NF3LNK
        } else {
            ftype3::NF3REG
        };

        // Get Unix permissions
        #[cfg(unix)]
        let mode = {
            use std::os::unix::fs::PermissionsExt;
            metadata.permissions().mode()
        };
        #[cfg(not(unix))]
        let mode = if metadata.is_dir() { 0o755 } else { 0o644 };

        // Get timestamps
        let mtime = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        let atime = metadata.accessed().unwrap_or(SystemTime::UNIX_EPOCH);
        let ctime = metadata.created().unwrap_or(SystemTime::UNIX_EPOCH);

        let to_nfstime = |t: SystemTime| {
            let duration = t.duration_since(SystemTime::UNIX_EPOCH).unwrap_or_default();
            nfstime3 {
                seconds: duration.as_secs() as u32,
                nseconds: duration.subsec_nanos(),
            }
        };

        Ok(fattr3 {
            ftype,
            mode,
            nlink: 1,
            uid: 501, // Default to current user
            gid: 20,  // Default to staff group
            size: metadata.len(),
            used: metadata.len(),
            rdev: specdata3::default(),
            fsid: 0,
            fileid: id,
            atime: to_nfstime(atime),
            mtime: to_nfstime(mtime),
            ctime: to_nfstime(ctime),
        })
    }
}

#[async_trait]
impl NFSFileSystem for PassthroughFS {
    fn root_dir(&self) -> fileid3 {
        1 // Root is always 1
    }

    fn capabilities(&self) -> VFSCapabilities {
        VFSCapabilities::ReadWrite
    }

    async fn write(&self, id: fileid3, offset: u64, data: &[u8]) -> Result<fattr3, nfsstat3> {
        let path = self.get_path(id).ok_or(nfsstat3::NFS3ERR_NOENT)?;

        let mut file = fs::OpenOptions::new()
            .write(true)
            .create(true)
            .open(&path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        use tokio::io::AsyncSeekExt;
        file.seek(std::io::SeekFrom::Start(offset))
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        file.write_all(data)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        self.path_to_fattr(&path, id).await
    }

    async fn create(
        &self,
        dirid: fileid3,
        filename: &filename3,
        _attr: sattr3,
    ) -> Result<(fileid3, fattr3), nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let name = std::str::from_utf8(filename).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let file_path = dir_path.join(name);

        fs::File::create(&file_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        let id = self.get_or_create_id(&file_path);
        let attr = self.path_to_fattr(&file_path, id).await?;

        Ok((id, attr))
    }

    async fn create_exclusive(
        &self,
        dirid: fileid3,
        filename: &filename3,
    ) -> Result<fileid3, nfsstat3> {
        let (id, _) = self.create(dirid, filename, sattr3::default()).await?;
        Ok(id)
    }

    async fn lookup(&self, dirid: fileid3, filename: &filename3) -> Result<fileid3, nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let name = std::str::from_utf8(filename).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let file_path = dir_path.join(name);

        if !file_path.exists() {
            return Err(nfsstat3::NFS3ERR_NOENT);
        }

        Ok(self.get_or_create_id(&file_path))
    }

    async fn getattr(&self, id: fileid3) -> Result<fattr3, nfsstat3> {
        let path = self.get_path(id).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        self.path_to_fattr(&path, id).await
    }

    async fn setattr(&self, _id: fileid3, _setattr: sattr3) -> Result<fattr3, nfsstat3> {
        // For now, just return current attrs
        // TODO: Actually set permissions, times, etc.
        self.getattr(_id).await
    }

    async fn read(
        &self,
        id: fileid3,
        offset: u64,
        count: u32,
    ) -> Result<(Vec<u8>, bool), nfsstat3> {
        let path = self.get_path(id).ok_or(nfsstat3::NFS3ERR_NOENT)?;

        let mut file = fs::File::open(&path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        use tokio::io::AsyncSeekExt;
        file.seek(std::io::SeekFrom::Start(offset))
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        let mut buffer = vec![0u8; count as usize];
        let bytes_read = file
            .read(&mut buffer)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        buffer.truncate(bytes_read);
        let eof = bytes_read < count as usize;

        Ok((buffer, eof))
    }

    async fn readdir(
        &self,
        dirid: fileid3,
        start_after: fileid3,
        max_entries: usize,
    ) -> Result<ReadDirResult, nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;

        let mut entries = Vec::new();
        let mut read_dir = fs::read_dir(&dir_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        let mut count = 0;
        while let Some(entry) = read_dir
            .next_entry()
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?
        {
            if count >= max_entries {
                return Ok(ReadDirResult {
                    entries,
                    end: false,
                });
            }

            let path = entry.path();
            let id = self.get_or_create_id(&path);

            // Skip entries before start_after
            if start_after != 0 && id <= start_after {
                continue;
            }

            let filename = entry.file_name();
            let name: filename3 = nfsstring(filename.to_string_lossy().as_bytes().to_vec());

            let attr = self.path_to_fattr(&path, id).await?;

            entries.push(DirEntry {
                fileid: id,
                name,
                attr,
            });

            count += 1;
        }

        Ok(ReadDirResult { entries, end: true })
    }

    async fn remove(&self, dirid: fileid3, filename: &filename3) -> Result<(), nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let name = std::str::from_utf8(filename).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let file_path = dir_path.join(name);

        let metadata = fs::metadata(&file_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_NOENT)?;

        if metadata.is_dir() {
            fs::remove_dir(&file_path)
                .await
                .map_err(|_| nfsstat3::NFS3ERR_IO)?;
        } else {
            fs::remove_file(&file_path)
                .await
                .map_err(|_| nfsstat3::NFS3ERR_IO)?;
        }

        Ok(())
    }

    async fn rename(
        &self,
        from_dirid: fileid3,
        from_filename: &filename3,
        to_dirid: fileid3,
        to_filename: &filename3,
    ) -> Result<(), nfsstat3> {
        let from_dir = self.get_path(from_dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let to_dir = self.get_path(to_dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;

        let from_name = std::str::from_utf8(from_filename).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let to_name = std::str::from_utf8(to_filename).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;

        let from_path = from_dir.join(from_name);
        let to_path = to_dir.join(to_name);

        fs::rename(from_path, to_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        Ok(())
    }

    async fn mkdir(
        &self,
        dirid: fileid3,
        dirname: &filename3,
    ) -> Result<(fileid3, fattr3), nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let name = std::str::from_utf8(dirname).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let new_dir_path = dir_path.join(name);

        fs::create_dir(&new_dir_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        let id = self.get_or_create_id(&new_dir_path);
        let attr = self.path_to_fattr(&new_dir_path, id).await?;

        Ok((id, attr))
    }

    async fn symlink(
        &self,
        dirid: fileid3,
        linkname: &filename3,
        symlink: &nfspath3,
        _attr: &sattr3,
    ) -> Result<(fileid3, fattr3), nfsstat3> {
        let dir_path = self.get_path(dirid).ok_or(nfsstat3::NFS3ERR_NOENT)?;
        let name = std::str::from_utf8(linkname).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let target = std::str::from_utf8(symlink).map_err(|_| nfsstat3::NFS3ERR_INVAL)?;
        let link_path = dir_path.join(name);

        #[cfg(unix)]
        tokio::fs::symlink(target, &link_path)
            .await
            .map_err(|_| nfsstat3::NFS3ERR_IO)?;

        #[cfg(not(unix))]
        return Err(nfsstat3::NFS3ERR_NOTSUPP);

        let id = self.get_or_create_id(&link_path);
        let attr = self.path_to_fattr(&link_path, id).await?;

        Ok((id, attr))
    }

    async fn readlink(&self, id: fileid3) -> Result<nfspath3, nfsstat3> {
        let path = self.get_path(id).ok_or(nfsstat3::NFS3ERR_NOENT)?;

        #[cfg(unix)]
        {
            let target = fs::read_link(&path)
                .await
                .map_err(|_| nfsstat3::NFS3ERR_IO)?;
            Ok(nfsstring(target.to_string_lossy().as_bytes().to_vec()))
        }

        #[cfg(not(unix))]
        Err(nfsstat3::NFS3ERR_NOTSUPP)
    }
}
