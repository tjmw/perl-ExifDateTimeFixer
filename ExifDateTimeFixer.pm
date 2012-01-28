package ExifDateTimeFixer;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::DateTime;
use MooseX::Method::Signatures;

use Image::ExifTool;

use DateTime;
use DateTime::Format::MySQL;
use DateTime::Format::Exif;

use feature 'say';

with 'MooseX::Getopt';

=head1 NAME

ExifDateTimeFixer

=head1 DESCRIPTION

Fixes the Exif datetime metadata on photos taken with my broken Panasonic
Lumix compact camera (broken buttons mean I can't set the date time so it's
way out).

It works by taking whatever the camera's definition of now is, as provided
by the user, figuring out how far out its clock is, and adjusting the date
time Exif data on photos accordingly.

=head1 SYNOPSIS

This module is designed to be run directly from the command line, though it
could also be invoked from a script if required.

The following command line flags are supported:

--camera_now

The camera's definition of now, in MySQL datetime format. Required.

--dry_run

Dry run only, don't write adjusted date time data back to file. Optional.

--time_zone

Time zone the photos were taken in. Optional. Defaults to "Europe/London".

Examples:

    perl ExifDateTimeFixer.pm --dry_run --verbose --camera_now "2008-06-08 06:08:00" ~/photos_with_bad_data/*.jpg

    perl ExifDateTimeFixer.pm --camera_now "2008-06-08 06:08:00" ~/photos_with_bad_data/*.jpg

    perl ExifDateTimeFixer.pm --time_zone "America/New_York" --camera_now "2008-06-08 06:08:00" ~/photos_with_bad_data/*.jpg

=head1 TODO

Better (any!) checking/validation of input data

=cut

# See http://search.cpan.org/~doy/Moose-2.0202/
#   lib/Moose/Manual/BestPractices.pod#Do_not_coerce_class_names_directly
subtype 'My::DateTime' => as class_type('DateTime');

coerce 'My::DateTime'
    => from 'Str'
    => via {
        DateTime::Format::MySQL->parse_datetime($_)
    };

# The camera's definition of now
has 'camera_now' => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
    trigger  => sub {
        # MooseX::Getopt doesn't know about DateTime so
        # use a trigger to set _camera_now_dt and do the 
        # coersion on that attribute
        my ($self, $value) = @_;
        $self->_camera_now_dt($value);
    },
);

# Don't actually update photos if set
has 'dry_run' => (
    is       => 'rw',
    isa      => 'Bool',
    required => 0,
    default  => 0,
);

has 'verbose' => (
    is       => 'rw',
    isa      => 'Bool',
    required => 0,
    default  => 0,
);

# Time zone
has 'time_zone' => (
    is       => 'rw',
    isa      => 'Str',
    required => 0,
    default  => 'Europe/London',
);

# Array ref of filenames
has '_photos' => (
    is       => 'ro',
    isa      => 'ArrayRef',
    default  => sub {
        shift->extra_argv
    },
);

# Exif tag list
has '_exif_tags' => (
    is       => 'ro',
    isa      => 'ArrayRef',
    default  => sub {
        [qw(DateTimeOriginal ModifyDate CreateDate)]
    },
);

# Camera's definition of now as a DateTime object.
# Set in trigger on camera_now
has '_camera_now_dt' => (
    is       => 'rw',
    isa      => 'My::DateTime',
    coerce   => 1,
    trigger  => sub {
        my ($self, $value) = @_;
        # Do this time_zone setting here since we don't have access
        # to $self in the coersion via method above
        $value->set_time_zone($self->time_zone);
    },
);

has '_camera_out_duration' => (
    is       => 'ro',
    isa      => 'DateTime::Duration',
    lazy     => 1,
    default  => sub {
        my ($self) = @_;
        DateTime->now(time_zone => $self->time_zone)
            - $self->_camera_now_dt
    },
);

=head1 METHODS

=head2 process_photos

Iterate over the photos specified, adjusting the Exif date time data,
as described above, based on the flags and file list provided.

=cut

method process_photos () {
    # Iterate over our list of photos, updating the specified tags
    for my $photo_filename (@{$self->_photos}) {
        my $exif = Image::ExifTool->new; 

        $exif->ExtractInfo($photo_filename);

        for my $tag (@{$self->_exif_tags}) {
            my $incorrect_exif_dt_string = $exif->GetValue($tag);

            my $incorrect_exif_dt =
                DateTime::Format::Exif->parse_datetime($incorrect_exif_dt_string)
                ->set_time_zone($self->time_zone);

            my $adjusted_exif_dt =
                $incorrect_exif_dt->clone->add_duration($self->_camera_out_duration);

            my $adjusted_exif_dt_string =
                DateTime::Format::Exif->format_datetime($adjusted_exif_dt);

            say "$photo_filename: modifying $tag"
                . " from $incorrect_exif_dt_string to $adjusted_exif_dt_string"
                if $self->verbose;

            $exif->SetNewValue($tag, $adjusted_exif_dt_string);
        }   

        $exif->WriteInfo($photo_filename) unless $self->dry_run;
    }
}

# I'm a modulino!
__PACKAGE__->new_with_options->process_photos unless caller();

=head1 AUTHOR

Tom Wey <tjmwey at gmail dot com>

=cut

1;
