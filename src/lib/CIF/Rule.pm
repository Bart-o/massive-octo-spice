package CIF::Rule;

use strict;
use warnings;

use Mouse;
use DateTime;
use Carp;
use Carp::Assert;
use CIF::Observable;
use CIF qw/$Logger parse_config normalize_timestamp is_url is_ip/;
use URI;
use URI::Escape;
use Data::Dumper;
use Data::Visitor::Callback;
use Regexp::Common qw/net/;
use Regexp::Common::net::CIDR;

use constant RE_IGNORE  => qw(qr/[\.]$/);
use constant RE_SKIP    => qr/remote|pattern|values|ignore|filters|datamap/;
use constant MIN_PREFIX => 14;


has [qw(store_content skip rule feed remote parser defaults disabled token cif_token cif_no_verify_ssl tlp_map)] => (
    is      => 'ro',
);

has 'not_before'    => (
    is          => 'ro',
    isa         => 'CIF::Type::DateTimeInt',
    coerce      => 1,
    default     => sub { DateTime->today()->epoch() },
);

has '_now' => (
    is          => 'ro', 
    default     => sub { time() },
);

sub set_not_before {
    my $self = shift;
    my $arg = shift;
    
    $self->{'not_before'} = normalize_timestamp($arg)->epoch;
}

sub process {
    my $self = shift;
    my $args = shift;
    
    $self->_merge_defaults($args);
    $self->_process_datamap($args);
    $self->_normalize_otype($args->{'data'});
    $self->_normalize_ts($args->{'data'});
    return $args->{'data'};
}

sub _process_datamap {
    my $self = shift;
    my $args = shift;

    my $datamap = $self->defaults->{'datamap'};
    return unless ( $datamap );

    foreach my $valName (keys %$datamap) {
        my $value = $args->{'data'}->{$valName} || $self->defaults->{$valName};
        unless ( $value ) {
            $Logger->error('Trying to use datamap on unexistant field '.$valName);
            assert($value);
        }

        # looking for all possible mapping
        my @newVals = ();
        foreach my $key (keys $datamap->{$valName}) {
            if ( index($value, $key) != -1 ) {
                push @newVals, $datamap->{$valName}->{$key};
            }
        }

        # mapping an array or a scalar, depending of the number of matched mapping
        my $newVal = undef;
        if ( scalar(@newVals) > 1 )
            {$newVal = \@newVals;}
        elsif ( scalar(@newVals) == 1 )
            {$newVal = pop @newVals;}
        elsif ( $datamap->{$valName}->{'_default'} )
            {$newVal = $datamap->{$valName}->{'_default'};}
        else
            {$newVal = $value;}

	$args->{'data'}->{$valName} = $newVal;
    }
}



sub _normalize_otype {
    my $self = shift;
    my $data = shift;

    _normalize_ip($data);
    _normalize_url($data);
}

sub _normalize_ip {
    my $data = shift;
    
    return if($data->{'otype'} && $data->{'otype'} ne 'ipv4');
    
    if(my $x = is_ip($data->{'observable'})){
        $data->{'otype'} = $x;
    } else {
        return;
    }
    
    if($data->{'observable'} =~ /^$RE{'net'}{'CIDR'}{'IPv4'}{'-keep'}$/){
        my $min = $data->{'min_prefix'} || MIN_PREFIX;
        if($2 < $min){
            $data->{'observable'} = $1.'/'.$min;
        }
    }      
}

sub _normalize_url {
    my $data = shift;
    
    my $x = is_url($data->{'observable'});
    return unless(defined($x));
    return if($x == 0 && ($data->{'otype'} && $data->{'otype'} ne 'url'));
 
    $data->{'observable'} = 'http://'.$data->{'observable'} if($x == 0 || $x == 2);
    
    $data->{'otype'} = 'url';
    
    $data->{'observable'} = uri_escape_utf8($data->{'observable'},'\x00-\x1f\x7f-\xff');
    $data->{'observable'} = lc(URI->new($data->{'observable'})->canonical->as_string);
}

sub _normalize_ts {
    my $self = shift;
    my $data = shift;
    
    $data->{'reporttime'} = normalize_timestamp($data->{'reporttime'});
    $data->{'reporttime'} = $data->{'reporttime'}->ymd().'T'.$data->{'reporttime'}->hms().'Z';
    
    if($data->{'firsttime'}){
        $data->{'firsttime'} = normalize_timestamp($data->{'firsttime'});
        $data->{'firsttime'} = $data->{'firsttime'}->ymd().'T'.$data->{'firsttime'}->hms().'Z';
    }
    
    if($data->{'lasttime'}){
        $data->{'lasttime'} = normalize_timestamp($data->{'lasttime'});
        $data->{'lasttime'} = $data->{'lasttime'}->ymd().'T'.$data->{'lasttime'}->hms().'Z';
        $data->{'firsttime'} = $data->{'lasttime'} unless($data->{'firsttime'});
    }
    
    return $data;
}

sub _merge_defaults {
    my $self = shift;
    my $args = shift;
    
    return unless($self->defaults);
    
    my $var_expansion_visitor = Data::Visitor::Callback->new(
        plain_value => sub { 
            if($_ && $_ =~ /<(\S+?)>/){
                my $default = $_;
                while ($_ =~ m/<(\S+?)>/g) {
                    # if we have something that requires expansion
                    # < >'s
                    my $val;
                    $val = $args->{'data'}->{$1} || $self->defaults->{$1};
                    unless($val){
                        $Logger->error('missing: '.$1 . ' make sure you add it to your mappings');
                        assert($val);
                    }
                    # replace the 'variable'
                    $default =~ s/<\Q$1\E>/$val/;
                }
                return $default;
            }
            return $_;
        }
    );
    
    foreach my $k (keys %{$self->defaults}){
        next if($k =~ RE_SKIP); 
        for($self->defaults->{$k}){
            $args->{'data'}->{$k} = $var_expansion_visitor->visit($self->defaults->{$k}) unless($args->{'data'}->{$k});
        }
    }
}

sub ignore {
    my $self = shift;
    my $arg = shift;

    foreach (RE_IGNORE){
        return 1 if($arg =~ $_);
    }
}

__PACKAGE__->meta->make_immutable();

1;
