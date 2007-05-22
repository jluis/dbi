package DBI::ProfileDumper::Apache;

=head1 NAME

DBI::ProfileDumper::Apache - capture DBI profiling data from Apache/mod_perl

=head1 SYNOPSIS

Add this line to your F<httpd.conf>:

  PerlSetEnv DBI_PROFILE 2/DBI::ProfileDumper::Apache

(If you're using mod_perl2, see L</When using mod_perl2> for some additional notes.)

Then restart your server.  Access the code you wish to test using a
web browser, then shutdown your server.  This will create a set of
F<dbi.prof.*> files in your Apache log directory.

Get a profiling report with L<dbiprof|dbiprof>:

  dbiprof /path/to/your/apache/logs/dbi.prof.*

When you're ready to perform another profiling run, delete the old files and start again.

=head1 DESCRIPTION

This module interfaces DBI::ProfileDumper to Apache/mod_perl.  Using
this module you can collect profiling data from mod_perl applications.
It works by creating a DBI::ProfileDumper data file for each Apache
process.  These files are created in your Apache log directory.  You
can then use the dbiprof utility to analyze the profile files.

=head1 USAGE

=head2 LOADING THE MODULE

The easiest way to use this module is just to set the DBI_PROFILE
environment variable in your F<httpd.conf>:

  PerlSetEnv DBI_PROFILE 2/DBI::ProfileDumper::Apache

The DBI will look after loading and using the module when the first DBI handle
is created.

It's also possible to use this module by setting the Profile attribute
of any DBI handle:

  $dbh->{Profile} = "2/DBI::ProfileDumper::Apache";

See L<DBI::ProfileDumper> for more possibilities, and L<DBI::Profile> for full
details of the DBI's profiling mechanism.

=head2 WRITING PROFILE DATA

The profile data files will be written to your Apache log directory by default.
You can use the C<DBI_PROFILE_APACHE_LOG_DIR> env var to change that. For example:

  PerlSetEnv DBI_PROFILE_APACHE_LOG_DIR /server_root/logs

=head3 When using mod_perl2

Under mod_perl2 you'll need to either set the C<DBI_PROFILE_APACHE_LOG_DIR> env var,
or enable the mod_perl2 C<GlobalRequest> option, like this:

  PerlOptions +GlobalRequest

to the global config section you're about test with DBI::ProfileDumper::Apache.
If you don't do one of those then you'll see messages in your error_log similar to:

  DBI::ProfileDumper::Apache on_destroy failed: Global $r object is not available. Set:
    PerlOptions +GlobalRequest in httpd.conf at ..../DBI/ProfileDumper/Apache.pm line 144

=head3 Naming the files

XXX

=head2 GATHERING PROFILE DATA

Once you have the module loaded, use your application as you normally
would.  Stop the webserver when your tests are complete.  Profile data
files will be produced when Apache exits and you'll see something like
this in your error_log:

  DBI::ProfileDumper::Apache writing to /usr/local/apache/logs/dbi.prof.2604.2619

Now you can use dbiprof to examine the data:

  dbiprof /usr/local/apache/logs/dbi.prof.2604.*

By passing dbiprof a list of all generated files, dbiprof will
automatically merge them into one result set.  You can also pass
dbiprof sorting and querying options, see L<dbiprof> for details.

=head2 CLEANING UP

Once you've made some code changes, you're ready to start again.
First, delete the old profile data files:

  rm /usr/local/apache/logs/dbi.prof. 

Then restart your server and get back to work.

=head1 MEMORY USAGE

DBI::Profile can use a lot of memory for very active applications because it
collects profiling data in memory for each distinct query run.
Calling C<flush_to_disk()> will write the current data to disk and free the
memory it's using. For example:

  $dbh->{Profile}->flush_to_disk() if $dbh->{Profile};

or, rather than flush every time, you could flush less often:

  $dbh->{Profile}->flush_to_disk()
    if $dbh->{Profile} and ++$i % 100;

=head1 AUTHOR

Sam Tregar <sam@tregar.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002 Sam Tregar

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl 5 itself.

=cut

our $VERSION = sprintf("2.%06d", q$Revision$ =~ /(\d+)/o);

our @ISA = qw(DBI::ProfileDumper);

use DBI::ProfileDumper;
use File::Spec;

use constant MP2 => ($ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} == 2) ? 1 : 0;

# Override flush_to_disk() to setup File just in time for output.
# Overriding new() would work unless the user creates a DBI handle
# during server startup, in which case all the children would try to
# write to the same file.
sub flush_to_disk {
    my $self = shift;
    
    # setup File per process
    my $path;
    if ($ENV{DBI_PROFILE_APACHE_LOG_DIR}) {
        $path = $ENV{DBI_PROFILE_APACHE_LOG_DIR};
    }
    else {
        if (MP2) {
            require Apache2::RequestUtil;
            require Apache2::ServerUtil;
            $path = Apache2::ServerUtil::server_root_relative(Apache2::RequestUtil->request()->pool, "logs/")
        }
        else {
            require Apache;
            $path = Apache->server_root_relative("logs/");
        }
    }

    # to be able to identify groups of profile files from the same set of
    # apache processes, we include the parent pid in the file name.
    my $parent_pid = getppid();

    my $filename = $self->filename();
    local $self->{File} = File::Spec->catfile($path, "$filename.$parent_pid.$$");

    print STDERR "DBI::ProfileDumper::Apache writing to $self->{File}\n"
        unless $self->{Quiet};

    # write out to disk
    return $self->SUPER::flush_to_disk(@_);
}

1;
