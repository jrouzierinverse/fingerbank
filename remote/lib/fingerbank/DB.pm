package fingerbank::DB;

=head1 NAME

fingerbank::DB

=head1 DESCRIPTION

Databases related interaction class

=cut

use strict;
use warnings;

use File::Copy qw(copy move);
use JSON;
use LWP::Simple qw(getstore);
use LWP::UserAgent;
use POSIX qw(strftime);

use fingerbank::Config;
use fingerbank::Constant qw($TRUE $FALSE);
use fingerbank::FilePath qw($INSTALL_PATH $LOCAL_DB_FILE $LOCAL_DB_SCHEMA $UPSTREAM_DB_FILE);
use fingerbank::Log;
use fingerbank::Schema::Local;
use fingerbank::Schema::Upstream;
use fingerbank::Util qw(is_success is_disabled);

our @schemas = ('Local', 'Upstream');

=head1 METHODS

=head2 connect

Returns the db handle for the requested schema

=cut

sub connect {
    my ( $self, $schema ) = @_;
    my $logger = fingerbank::Log::get_logger;

    $logger->debug("Requested schema '$schema' db handle");

    # Check if the requested schema is a valid one
    my %schemas = map { $_ => 1 } @schemas;
    if ( !exists($schemas{$schema}) ) {
        $logger->warn("Requested schema '$schema' does not exists");
        return;
    }

    # Returning the requested schema db handle
    return "fingerbank::Schema::$schema"->connect("dbi:SQLite:" . $INSTALL_PATH . "db/fingerbank_$schema.db");
}

=head2 fetch_upstream

Download the latest version of the upstream Fingerbank database

=cut

sub fetch_upstream {
    my ( $self, $is_updating ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $Config = fingerbank::Config::get_config;

    if ( !fingerbank::Config::is_api_key_configured ) {
        $logger->warn("Can't communicate with Fingerbank project without a valid API key.");
        return;
    }

    my $database_file = $UPSTREAM_DB_FILE;
    $database_file = $database_file . ".new" if ( defined($is_updating) && $is_updating );
    my $download_url = $Config->{'upstream'}{'db_url'} . $Config->{'upstream'}{'api_key'};

    $logger->debug("Downloading the latest version of upstream database from '$download_url' to '$database_file'");

    my $status = getstore($download_url, $database_file);

    if ( is_success($status) ) {
        $logger->info("Successfully fetched 'Upstream' database from Fingerbank project");
    } else {
        $logger->warn("Failed to download latest version of 'Upstream' database with the following return code: $status");
    }

    return $status;
}

=head2 initialize_local

Create with the appropriate schema, the local version of the Fingerbank database

Will also make sure a local instance doesn't already exists.

=cut

sub initialize_local {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $database_file   = $LOCAL_DB_FILE;
    my $schema_file     = $LOCAL_DB_SCHEMA;

    if ( -f $database_file ) {
        $logger->warn("Tried to initialize 'Local' database by applying default schema on an existing database. Exiting");
        return;
    }

    $logger->debug("Initializing 'Local' database by applying default schema");
    system("sqlite3 $database_file < $schema_file");
    if ( $? != 0 ) {
        $logger->warn("Failed to initialize 'Local' database when applying default schema");
        return;
    } else {
        $logger->info("Successfully initialized 'Local' database by applying default schema");
    }
}

=head2 update_upstream

Update the existing 'upstream' database by taking care of backing up the current one

=cut

sub update_upstream {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my ( $status, $status_msg );

    my $database_file = $UPSTREAM_DB_FILE;

    my $is_an_update;
    if ( -f $database_file ) {
        $is_an_update = $TRUE;
    } else {
        $is_an_update = $FALSE;
    }
    $status = fetch_upstream($self, $is_an_update);

    if ( is_success($status) && $is_an_update ) {
        my $date                    = POSIX::strftime( "%Y%m%d_%H%M%S", localtime );
        my $database_file_backup    = $database_file . "_$date";
        my $database_file_new       = $database_file . ".new";

        my $return_code;

        # We create a backup of the actual upstream database file
        $logger->debug("Backing up actual 'upstream' database file to '$database_file_backup'");
        $return_code = copy($database_file, $database_file_backup);

        # If copy operation succeed
        if ( $return_code == 1 ) {
            # We move the newly downloaded upstream database file to the existing one
            $logger->debug("Moving new 'upstream' database file to existing one");
            $return_code = move($database_file_new, $database_file);
        }

        # Handling error in either copy or move operation
        if ( $return_code == 0 ) {
            $status = $fingerbank::Status::INTERNAL_SERVER_ERROR;
            $logger->warn("An error occured while copying / moving files during 'upstream' database update process: $!");
        }
    }

    if ( is_success($status) ) {
        $status_msg = "Successfully updated Fingerbank 'upstream' database file";
        $logger->info($status_msg);

        return ( $status, $status_msg );
    }

    $status_msg = "An error occured while updating Fingerbank 'upstream' database file";
    $logger->warn($status_msg);

    return ( $status, $status_msg )
}

=head2 submit_unknown

Not yet implemented

=cut

sub submit_unknown {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my ( $status, $status_msg );

    my $Config = fingerbank::Config::get_config;

    if ( !fingerbank::Config::is_api_key_configured ) {
        $logger->warn("Can't communicate with Fingerbank project without a valid API key.");
        return;
    }

    # Are we configured to do so ?
    my $record_unmatched = $Config->{'query'}{'record_unmatched'};
    if ( is_disabled($record_unmatched) ) {
        $logger->debug("Not configured to record unmatched parameters. Cannot submit so skipping");
        return;
    }

    $logger->debug("Attempting to submit unmatched parameters to upstream Fingerbank project");

    my $db = fingerbank::DB->connect('Local');
    my $resultset = $db->resultset('Unmatched')->search({ 'submitted' => $FALSE }, { columns => ['id', 'type', 'value'], order_by => { -asc => 'id' } });

    my ( $id, %data );
    foreach my $entry ( $resultset ) {
        while ( my $row = $entry->next ) {
            push ( @{ $data{$row->type} }, $row->value );
        }
    }

    my $ua = LWP::UserAgent->new;
    my $submitted_data = encode_json(\%data);

    my $req = HTTP::Request->new( POST => $Config->{'upstream'}{'submit_url'}.$Config->{'upstream'}{'api_key'} );
    $req->content_type('application/json');
    $req->content($submitted_data);

    my $res = $ua->request($req);

    if ( $res->is_success ) {
        $status = $fingerbank::Status::OK;
        $resultset->update( { 'submitted' => $TRUE } );
        $status_msg = "Successfully submitted unmatched arguments to upstream Fingerbank project";
        $logger->info($status_msg);
    } else {
        $status = $fingerbank::Status::INTERNAL_SERVER_ERROR;
        $status_msg = "An error occured while submitting unmatched arguments to upstream Fingerbank project";
        $logger->warn($status_msg . ": " . $res->status_line);
    }

    return ( $status, $status_msg );
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2015 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;