package ExifDateTimeFixer;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::DateTime qw(TimeZone);
use MooseX::Method::Signatures;

use Image::ExifTool;

use DateTime;
use DateTime::Format::MySQL;

with 'MooseX::Getopt';

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

# Time zone of the camera
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
    default  => sub { shift->extra_argv },
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
        $value->set_time_zone($self->time_zone)
            ->set_time_zone('UTC'); 
    },
);

has '_camera_off_duration' => (
    is       => 'ro',	
    isa      => 'DateTime::Duration',
    lazy     => 1,
    default  => sub {
        my ($self) = @_;
        DateTime->now(time_zone => 'UTC')
            - $self->_camera_now_dt
    },
);

method process_photos () {
    my @exif_tags = qw(DateTimeOriginal ModifyDate CreateDate);

    # Iterate over our list of photos, updating the specified tags
    for my $photo_filename (@{$self->_photos}) {
        my $exif = Image::ExifTool->new; 

        $exif->ExtractInfo($photo_filename);

        for my $tag (@exif_tags) {
            my $existing_exif_datetime_string = $exif->GetValue($tag);

            my $exif_datetime =
                $self->_parse_camera_formatted_datetime($existing_exif_datetime_string);

            my $adjusted_exif_datetime =
                $exif_datetime->clone->add_duration($self->_camera_off_duration);

            my $adjusted_exif_datetime_string =
                $self->_build_camera_formatted_datetime($adjusted_exif_datetime);

            print "$photo_filename: modifying $tag"
                . " from $existing_exif_datetime_string to $adjusted_exif_datetime_string\n";

            $exif->SetNewValue($tag, $adjusted_exif_datetime_string);
        }   

        $exif->WriteInfo($photo_filename) unless $self->dry_run;
    }
}

# TODO: Abstract the following two methods into DateTime::Format::Panasonic
# (or a similarly named class)

# Parse Panasonic camera date format
method _parse_camera_formatted_datetime (Str $datetime) {
    my ($date, $time) = split ' ', $datetime;

    my %datetime;

    @datetime{qw(year month day)}     = split ':', $date;
    @datetime{qw(hour minute second)} = split ':', $time;

    return DateTime->new(
        %datetime,
        time_zone => $self->time_zone,
    )->set_time_zone('UTC');
}

# Create DateTime object from Panasonic camera date format
method _build_camera_formatted_datetime(DateTime $datetime) {
    $datetime->set_time_zone($self->time_zone);

    return sprintf("%d:%02d:%02d %02d:%02d:%02d",
        $datetime->year,
        $datetime->month,
        $datetime->day,
        $datetime->hour,
        $datetime->minute,
        $datetime->second,
    );
}

# I'm a modulino yo!
__PACKAGE__->new_with_options()->process_photos unless caller();
