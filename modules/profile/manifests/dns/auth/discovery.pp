# DNS Service Discovery Config
class profile::dns::auth::discovery(
    Hash $discovery_services = lookup('discovery::services'),
    Hash $lvs_services = lookup('lvs::configuration::lvs_services'),
    String $conftool_prefix = lookup('conftool_prefix'),
) {
    file { '/etc/gdnsd/discovery-geo-resources':
        ensure  => 'present',
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => template('profile/dns/auth/discovery-geo-resources.erb'),
        notify  => Service['gdnsd'],
        before  => Exec['authdns-local-update'],
    }

    file { '/etc/gdnsd/discovery-metafo-resources':
        ensure  => 'present',
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => template('profile/dns/auth/discovery-metafo-resources.erb'),
        notify  => Service['gdnsd'],
        before  => Exec['authdns-local-update'],
    }

    file { '/etc/gdnsd/discovery-states':
        ensure  => 'present',
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        content => template('profile/dns/auth/discovery-states.erb'),
        notify  => Service['gdnsd'],
        before  => Exec['authdns-local-update'],
    }

    file { '/etc/gdnsd/discovery-map':
        ensure => 'present',
        mode   => '0444',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/profile/dns/auth/discovery-map',
        notify => Service['gdnsd'],
        before => Exec['authdns-local-update'],
    }

    class { 'confd':
        prefix => $conftool_prefix,
    }

    $discovery_services.each |$svc_name,$svc_data| {
        $keyspace = '/discovery'
        $check = $svc_data['active_active'] ? {
            false => '/usr/local/bin/authdns-check-active-passive',
            true  => undef,
        }
        confd::file { "/var/lib/gdnsd/discovery-${svc_name}.state":
            uid        => '0',
            gid        => '0',
            mode       => '0444',
            content    => template('profile/dns/auth/discovery-statefile.tpl.erb'),
            watch_keys => ["${keyspace}/${svc_name}"],
            check      => $check,
        }
    }
}
