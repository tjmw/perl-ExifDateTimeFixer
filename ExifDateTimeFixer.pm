package ExifDateTimeFixer;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::DateTime qw(TimeZone);
use MooseX::Method::Signatures;

use Image::ExifTool;

use DateTime;
use DateTime::Format::MySQL;

with 'MooseX::Getopt';

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

has 'dry_run' => (
    is       => 'rw',
    isa      => 'Bool',
    required => 0,
    default  => 0,
);

has '_photos' => (
    is       => 'ro',
    isa      => 'ArrayRef',
    default  => sub { shift->extra_argv },
);

# See http://search.cpan.org/~doy/Moose-2.0202/
#   lib/Moose/Manual/BestPractices.pod#Do_not_coerce_class_names_directly
subtype 'My::DateTime' => as class_type('DateTime');

coerce 'My::DateTime'
	=> from 'Str'
		=> via {
            DateTime::Format::MySQL->parse_datetime($_)
                ->set_time_zone('UTC');
        };

has '_camera_now_dt' => (
    is       => 'rw',
    isa      => 'My::DateTime',
    coerce   => 1,
);

has '_camera_off_duration' => (
    is       => 'ro',	
    isa      => 'DateTime::Duration',
    lazy     => 1,
    default  => sub {
        DateTime->now(time_zone => 'UTC')
            - shift->_camera_now_dt
    },
);

method process_photos () {
    my @tags = qw(DateTimeOriginal ModifyDate CreateDate);

    # Iterate over our list of photos, updating the specified tags
    for my $photo_filename (@{$self->_photos}) {
        my $exif = Image::ExifTool->new; 

        $exif->ExtractInfo($photo_filename);

        for my $tag (@tags) {
            my $existing_datetime_string = $exif->GetValue($tag);

            my $camera_datetime =
                $self->parse_camera_formatted_datetime($existing_datetime_string)
                ->set_time_zone('UCT');

            my $adjusted_datetime =
                $camera_datetime->clone->add_duration($camera_out_duration);

            my $adjusted_datetime_string =
                $self->build_camera_formatted_datetime($adjusted_datetime);

            print "$photo_filename: updating $tag"
                . " from $existing_datetime_string to $adjusted_datetime_string\n";

            $exif->SetNewValue($tag, $adjusted_datetime_string);
        }   

        $exif->WriteInfo($photo_filename) unless $self->dry_run;
    }
}

method parse_camera_formatted_datetime (Str $datetime) {
    my ($date, $time) = split ' ', $datetime;

    my %datetime;

    @datetime{qw(year month day)}     = split ':', $date;
    @datetime{qw(hour minute second)} = split ':', $time;

    return DateTime->new(
        %datetime,
        time_zone => 'UTC',
    );
}

method build_camera_formatted_datetime(DateTime $datetime) {

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
