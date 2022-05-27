# perl-IPC-Open3-example

Perl's `IPC::Open3` has poor [documentation](https://perldoc.perl.org/IPC/Open3.html) and no examples.

Perl's `IPC::Run3` is unable to perform async IO (does not have a "pump()" facility)

Perl's `IPC::Run2` has bugs, including the inability to close a stream without buffering all final output in RAM (which might be tens or hundreds of gigs if you're reading from a brotli stream), and that code is utterly unmaintable

This `perl-IPC-Open3-example` working example shows how to write to and read from subcommands, including their errors.  This example is also a better working example as an alternative to IPC::Run2

It doesn't block, and should be safe to run multiple times in a chain - e.g. if you're tring to stream a compressed file that is inside some other compressed file or whatever.
