require "./spec_helper"
require "../src/cli"

describe JJFS::CLI do
  it "parses init command" do
    cli = JJFS::CLI.new(["init"])
    cli.command.should eq(:init)
    cli.args.should be_empty
  end

  it "parses init with repo name" do
    cli = JJFS::CLI.new(["init", "work-notes"])
    cli.command.should eq(:init)
    cli.args.should eq(["work-notes"])
  end

  it "parses open command" do
    cli = JJFS::CLI.new(["open", "default"])
    cli.command.should eq(:open)
    cli.args.should eq(["default"])
  end
end
