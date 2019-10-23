#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use Cache::Memcached::Fast::Safe;
use Furl;
use HTTP::Status qw(:constants status_message);
use JSON::XS;
use Plack::Builder;
use Plack::Request;
use Time::HiRes qw(usleep);
use URI;

my @containers = qw/
    app_sample
/;
my $endpoint = 'http://sock-proxy:2375';
my $apikey   = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';
my $shutting_seconds = 30;

#####

my $furl = Furl->new(timeout => 1);
my $memd = Cache::Memcached::Fast::Safe->new(+{
    servers => ['memcached:11211'],
    namespace => 'dondemand',
});

sub get {
    my $req = shift;

    $req->uri->path =~ m|/(.*)/-/(.*)|;
    my ($container, $test_endpoint) = ($1, $2);

    unless (grep { $container eq $_ } @containers) {
        return [HTTP_BAD_REQUEST, [], [status_message(HTTP_BAD_REQUEST)]];
    }

    if (my $val = $memd->get(memd_key($container))) {
        $memd->set(memd_key($container) => time);
        return [HTTP_OK, [], []];
    }

    my $code = get_vm($container);

    if (not defined $code) {
        return [HTTP_SERVICE_UNAVAILABLE, [], []];
    }

    # check alive test_endpoint when docker start.
    my $check = 0;
    while($code == HTTP_CREATED && 50 > $check) {
        usleep(100 * 1000); # 100msec
        my $res = $furl->get($test_endpoint);
        last if $res->is_success;
        $check++;
    }
    $memd->set(memd_key($container) => time);

    return [$code, [], []];
}

sub _delete {
    my $req = shift;

    $req->uri->path =~ m|/(.*)|;
    my $container = $1;

    unless (grep { $container eq $_ } @containers) {
        return [HTTP_BAD_REQUEST, [], [status_message(HTTP_BAD_REQUEST)]];
    }

    # https://docs.docker.com/engine/api/v1.39/#operation/ContainerStop
    $furl->post(sprintf('%s/containers/%s/stop', $endpoint, $container));
    $memd->delete(memd_key($container));

    return [HTTP_ACCEPTED, [], []];
}

sub purge { 
    my $req = shift;

    if ($req->uri->path ne "/$apikey") {
        return [HTTP_BAD_REQUEST, [], [status_message(HTTP_BAD_REQUEST)]];
    }

    my $force = $req->param('force') or 0;
    foreach my $container (@containers) {
        my $time = $memd->get(memd_key($container));
        if ($force or (defined $time && $time + $shutting_seconds < time)) {
            # https://docs.docker.com/engine/api/v1.39/#operation/ContainerStop
            $furl->post(sprintf('%s/containers/%s/stop', $endpoint, $container));
            $memd->delete(memd_key($container));
            warn "shutting down : $container";
        }
    }

    return [HTTP_ACCEPTED, [], []];
}

sub get_vm {
    my $container = shift;

    my $res = create_get_request($container);
    return undef unless $res->is_success;

    my $h = decode_json($res->content);

    # State is...
    # created|restarting|running|removing|paused|exited|dead
    my $state = lc($h->[0]{State});
    if ($state =~ /running|created|restarting/) {
        return HTTP_OK;

    } elsif ($state eq 'exited') {

        # https://docs.docker.com/engine/api/v1.39/#operation/ContainerStart
        $furl->post(sprintf('%s/containers/%s/start', $endpoint, $container));
        warn "container start: $container";

        my $check = 0;
        while(10 > $check) {
            usleep(100 * 1000); # 100msec
            my $res2 = create_get_request($container);
            return undef unless $res2->is_success;

            my $h = decode_json($res2->content);
            my $state = lc($h->[0]{State});
            if ($state eq 'running') {
                return HTTP_CREATED;
            }
            $check++;
        }
    }
    return undef;
}

sub create_get_request {
    my $container = shift;

    my $u = URI->new(sprintf('%s/containers/json', $endpoint));
    $u->query_form(
        filters => encode_json({
            name => {
                $container => JSON::XS::true
            },
        }),
        all => 'true',
    );

    # https://docs.docker.com/engine/api/v1.39/#operation/ContainerList
    $furl->get($u->as_string);
}

sub memd_key { 
    my $container = shift;
    "dondemand:info:$container";
}

builder {
    enable 'AccessLog::Timed', format => "%h %l %u %t \"%r\" %>s %b %D";
    enable 'HTTPExceptions';
    sub {
        my $env = shift;
        my $req = Plack::Request->new($env);
        if ($req->method eq 'GET') {
            return get($req);
        } elsif ($req->method eq 'DELETE') {
            return _delete($req);
        } elsif ($req->method eq 'PURGE') {
            $env->{REQUEST_URI} = "(censored)";
            return purge($req);
        }
        return [HTTP_SERVICE_UNAVAILABLE, [], []];
    };
};

