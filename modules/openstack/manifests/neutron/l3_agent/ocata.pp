class openstack::neutron::l3_agent::ocata(
    $dmz_cidr_array,
    $network_public_ip,
    $report_interval,
) {
    class { "openstack::neutron::l3_agent::ocata::${::lsbdistcodename}": }

    $dmz_cidr = join($dmz_cidr_array, ',')
    file { '/etc/neutron/l3_agent.ini':
            owner   => 'neutron',
            group   => 'neutron',
            mode    => '0640',
            content => template('openstack/ocata/neutron/l3_agent.ini.erb'),
            require => Package['neutron-l3-agent'];
    }
}
