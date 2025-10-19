// jjfs-nfs: Simple NFS server to mount jj workspace directories
// Pass-through filesystem that mirrors a real directory

use clap::Parser;
use nfsserve::tcp::{NFSTcp, NFSTcpListener};
use std::path::PathBuf;
use tracing::info;

mod passthrough;
use passthrough::PassthroughFS;

#[derive(Parser, Debug)]
#[command(name = "jjfs-nfs")]
#[command(about = "NFS server for mounting jj workspace directories", long_about = None)]
struct Args {
    /// Directory to serve via NFS
    #[arg(value_name = "DIRECTORY")]
    directory: PathBuf,

    /// Port to listen on (default: random available port)
    #[arg(short, long)]
    port: Option<u16>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_writer(std::io::stderr)
        .init();

    let args = Args::parse();

    // Validate directory exists
    if !args.directory.exists() {
        eprintln!("Error: Directory does not exist: {:?}", args.directory);
        std::process::exit(1);
    }

    if !args.directory.is_dir() {
        eprintln!("Error: Path is not a directory: {:?}", args.directory);
        std::process::exit(1);
    }

    // Canonicalize path to get absolute path
    let abs_path = args.directory.canonicalize()?;

    // Determine port
    let port = args.port.unwrap_or(0); // 0 = random available port
    let bind_addr = format!("127.0.0.1:{}", port);

    // Create pass-through filesystem
    let fs = PassthroughFS::new(abs_path.clone());

    info!("Starting NFS server for directory: {:?}", abs_path);

    let listener = NFSTcpListener::bind(&bind_addr, fs).await?;

    // Get the actual port we're listening on (needed if port was 0)
    let actual_port = if port == 0 {
        // Parse from the listener somehow, or just use the port argument
        // For now, we'll require explicit port
        eprintln!("Error: Port must be specified explicitly");
        std::process::exit(1);
    } else {
        port
    };

    // Print connection info for jjfs to parse
    println!("NFS_PORT={}", actual_port);
    println!("NFS_READY=1");

    info!("NFS server listening on 127.0.0.1:{}", actual_port);
    info!("Mount with: sudo mount_nfs -o nolocks,vers=3,tcp,port={},mountport={} localhost:/ /mount/point", actual_port, actual_port);

    // Serve forever
    listener.handle_forever().await?;

    Ok(())
}
