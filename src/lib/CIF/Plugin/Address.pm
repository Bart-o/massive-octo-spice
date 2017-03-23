package CIF::Plugin::Address;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration   use CIF ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
    is_address protocol_to_int is_ip is_ipv4 is_ipv6 is_protocol
    is_ip is_ip_private is_fqdn is_email is_asn is_fqdn_lazy
    is_url is_url_broken
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(

);
require Mail::RFC822::Address;
use URI; ##TODO -- change from regexs
use Regexp::Common qw/net/;
use Regexp::Common::net::CIDR;
use Net::Patricia;
use Try::Tiny;

use constant RE_FQDN_LAZY       => qr/^$RE{net}{domain}{-rfc1101}{-nospace}$/;
#use constant RE_FQDN            => qr/^(?:[0-9a-zA-Z-]{1,63}\.)+[a-zA-Z]{2,63}$/; # https://groups.google.com/forum/#!topic/ci-framework/VDUxNd5rPf8
use constant RE_FQDN            => qr/^((xn--)?(--)?[a-zA-Z0-9-_]+(-[a-zA-Z0-9]+)*\.)+[a-zA-Z]{2,}(--p1ai)?$/; # http://goo.gl/Cztyn2 -- probably needs more work
use constant RE_IPV4            => qr/^$RE{'net'}{'IPv4'}$/;
use constant RE_IPV4_CIDR       => qr/^$RE{'net'}{'CIDR'}{'IPv4'}$/;
use constant RE_IPV6            => qr/^$RE{'net'}{'IPv6'}/;
use constant ASN_MAX            => 2**32 - 1;
use constant URI_SCHEMES        => qr/^(https?|ftp)$/;

my @ipv4_private_addresses = (
    "0.0.0.0/8",
    "10.0.0.0/8",
    "127.0.0.0/8",
    "192.168.0.0/16",
    "172.16.0.0.12",
    "169.254.0.0/16",
    "192.0.2.0/24",
    "224.0.0.0/4",
    "240.0.0.0/5",
    "248.0.0.0/5"
);

my $ipv4_private = Net::Patricia->new;
$ipv4_private->add_string($_) for(@ipv4_private_addresses);

my $protocols = {
    icmp    => 1,
    tcp     => 6,
    udp     => 17,
};

sub protocol_to_int {
    my $proto = shift;
    
    return -1 unless $proto;
    
    return $protocols->{$proto} || -1;
}

sub is_protocol {
    my $proto = shift;
    return 1 if($protocols->{$proto});
}

sub is_address {
    my $arg = shift || return 0;
    
    return 'ip'         if(is_ip($arg));
    return 'asn'        if(is_asn($arg));
    return 'email'      if(is_email($arg));
    return 'fqdn'       if(is_fqdn($arg));
    return 'url'        if(is_url($arg));
    return 'url_broken' if(is_url_broken($arg));
}

sub is_asn {
    my $arg = shift || return 0;
    
    return 1 if($arg =~ /^\d+$/ && ($arg > 0 && $arg <= ASN_MAX()));
}

sub is_email {
    my $arg = shift || return 0;
    
    return 1 if(Mail::RFC822::Address::valid($arg));
}

sub is_fqdn {
    my $arg = shift || return;
    return 1 if($arg =~ RE_FQDN());
}

sub is_fqdn_lazy {
    my $arg = shift || return;
    
    return 1 if($arg =~ RE_FQDN_LAZY());
}

sub is_url {
    my $arg = shift || return;
    my $uri = URI->new($arg);
    return 0 unless($uri->scheme);
    return 0 unless($uri->scheme =~ URI_SCHEMES);
    return 0 unless(is_fqdn($uri->host) or is_ip($uri->host));
    return 1;
}

sub is_url_broken {
    my $arg = shift || return;
    return 0 if(is_url($arg));
    return 0 unless($arg =~ RE_URL_BROKEN());
    # if it really matches 1.2.3.0/16, return 0
    return 0 if($arg =~ /^\b(?:\d{1,3}\.){3}\d{1,3}\b\/(\d{1,2})$/);
    return 1;
}

sub is_ip_private {
    my $ip = shift || return 0;
    return 0 unless(is_ip($ip));
    my ($ret, $err);
    try {
        if($ip =~ /^(\S+)\/\d+$/){
            $ret = $ipv4_private->match($1);
        } else {
            $ret = $ipv4_private->match($ip);
        }
    } catch {
        $err = shift;
    };
    return 0 if($err);
    return $ret;
}

sub is_ip {
    my $arg = shift || return 0;
    
    return 0 if is_url($arg,1);
    return 0 if is_fqdn($arg);
    
    return 'ipv4' if(is_ipv4($arg));
    return 'ipv6' if(is_ipv6($arg));
    
    return 0;
}

sub is_ipv4 {
    my $arg = shift || return;

    return 1 if($arg =~ RE_IPV4);
    if($arg =~ RE_IPV4_CIDR){
        if($arg =~ /^\S+\/(\d+)$/){
            if($1 && $1 < 8){
                return 0;
            } else {
                return 1;
            }
        } else {
            return 1;
        }
    };
    
}

sub is_ipv6 {
    my $arg = shift || return;
    
    return 1 if($arg =~ RE_IPV6);
}

1;
