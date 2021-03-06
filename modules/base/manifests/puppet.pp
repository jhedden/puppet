class base::puppet(
    Stdlib::Filesource              $ca_source,
    Boolean                         $manage_ca_file         = false,
    Stdlib::Unixpath                $ca_file_path           = '/var/lib/puppet/ssl/certs/ca.pem',
    String                          $ca_server              = '',
    Stdlib::Host                    $server                 = 'puppet',
    Optional[String]                $certname               = undef,
    Optional[String]                $dns_alt_names          = undef,
    Optional[String]                $environment            = undef,
    Integer                         $interval               = 30,
    Integer[4,5]                    $puppet_major_version   = 5,
    Integer[2,3]                    $facter_major_version   = 3,
    Enum['pson', 'json', 'msgpack'] $serialization_format   = 'json',
    Optional[Enum['chain', 'leaf']] $certificate_revocation = undef,
) {
    include ::passwords::puppet::database # lint:ignore:wmf_styleguide

    $crontime          = fqdn_rand(60, 'puppet-params-crontime')

    # On buster simply install the distro defaults of facter/puppet
    if os_version('debian < buster') {
      if $puppet_major_version == 5 {
        apt::repository {'component-puppet5':
          uri        => 'http://apt.wikimedia.org/wikimedia',
          dist       => "${::lsbdistcodename}-wikimedia",
          components => 'component/puppet5',
          before     => Package['puppet'],
          notify     => Exec['apt_update_puppet5'],
        }

        apt::pin { 'puppet5-stretch':
            pin      => 'release c=component/puppet5',
            priority => '1002',
            before   => Package['puppet'],
        }

        exec {'apt_update_puppet5':
            command     => '/usr/bin/apt-get update',
            refreshonly => true,
        }

        Package['puppet'] {
            require => [Apt::Repository['component-puppet5'], Exec['apt_update_puppet5']],
        }

      } elsif $puppet_major_version == 4 {
        apt::repository {'component-puppet5':
          ensure => absent,
        }
      }

      if $facter_major_version == 3 {
        apt::repository {'component-facter3':
          uri        => 'http://apt.wikimedia.org/wikimedia',
          dist       => "${::lsbdistcodename}-wikimedia",
          components => 'component/facter3',
          before     => Package['facter'],
          notify     => Exec['apt_update_facter'],
        }

        apt::pin { 'facter3-stretch':
            pin      => 'release c=component/facter3',
            priority => '1002',
            before   => Package['facter'],
        }

        Package['facter'] {
            require => [Apt::Repository['component-facter3'], Exec['apt_update_facter']],
        }

        exec {'apt_update_facter':
            command     => '/usr/bin/apt-get update',
            refreshonly => true,
        }

      } elsif $facter_major_version == 2 {
        apt::repository {'component-facter3':
          ensure => absent,
        }
      }
    }

    # augparse is required to resolve the augeasversion in facter3
    # facter needs virt-what for proper "virtual"/"is_virtual" resolution
    package { [ 'facter', 'puppet', 'augeas-tools', 'virt-what' ]:
        ensure => present,
    }

    if $manage_ca_file {
        file{ $ca_file_path:
            ensure => file,
            owner  => 'puppet',
            group  => 'puppet',
            mode   => '0644',
            source => $ca_source,
        }
    }
    file { '/etc/puppet/puppet.conf':
        ensure => 'file',
        owner  => 'root',
        group  => 'root',
        mode   => '0444',
        notify => Exec['compile puppet.conf'],
    }

    file { '/etc/puppet/puppet.conf.d/':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0550',
    }

    file { ['/etc/puppetlabs/','/etc/puppetlabs/facter/']:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
    }

    file { '/etc/puppetlabs/facter/facter.conf':
        ensure  => 'file',
        owner   => 'root',
        group   => 'root',
        mode    => '0444',
        source  => 'puppet:///modules/base/puppet/facter.conf',
        require => File['/etc/puppetlabs/facter/'],
    }

    base::puppet::config { 'main':
        prio    => 10,
        content => template('base/puppet.conf.d/10-main.conf.erb'),
    }

    # Compile /etc/puppet/puppet.conf from individual files in /etc/puppet/puppet.conf.d
    exec { 'compile puppet.conf':
        path        => '/usr/bin:/bin',
        command     => 'cat /etc/puppet/puppet.conf.d/??-*.conf > /etc/puppet/puppet.conf',
        refreshonly => true,
    }

    ## do not use puppet agent, use a cron-based puppet-run instead
    service {'puppet':
        ensure => stopped,
        enable => false,
    }

    file { '/usr/local/share/bash/puppet-common.sh':
        mode   => '0555',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/puppet-common.sh',
    }

    file { '/usr/local/sbin/puppet-run':
        mode    => '0555',
        owner   => 'root',
        group   => 'root',
        content => template('base/puppet-run.erb'),
    }

    file { '/usr/local/sbin/disable-puppet':
        ensure => present,
        mode   => '0550',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/disable-puppet',
    }

    file { '/usr/local/sbin/enable-puppet':
        ensure => present,
        mode   => '0550',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/enable-puppet',
    }

    file { '/usr/local/sbin/run-puppet-agent':
        ensure => present,
        mode   => '0550',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/run-puppet-agent',
    }

    file { '/usr/local/sbin/run-no-puppet':
        mode   => '0550',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/run-no-puppet',
    }

    file { '/etc/cron.d/puppet':
        mode    => '0444',
        owner   => 'root',
        group   => 'root',
        content => template('base/puppet.cron.erb'),
        require => File['/usr/local/sbin/puppet-run'],
    }

    logrotate::rule { 'puppet':
        ensure       => present,
        file_glob    => '/var/log/puppet /var/log/puppet.log',
        frequency    => 'daily',
        compress     => true,
        missing_ok   => true,
        not_if_empty => true,
        rotate       => 7,
    }

    rsyslog::conf { 'puppet-agent':
        source   => 'puppet:///modules/base/rsyslog.d/puppet-agent.conf',
        priority => 10,
        require  => File['/etc/logrotate.d/puppet'],
    }

    # Mode 0751 to make sure non-root users can access
    # /var/lib/puppet/state/agent_disabled.lock to check if puppet is enabled
    file { '/var/lib/puppet':
        ensure => directory,
        owner  => 'puppet',
        group  => 'puppet',
        mode   => '0751',
    }

    file { '/usr/local/bin/puppet-enabled':
        mode   => '0555',
        owner  => 'root',
        group  => 'root',
        source => 'puppet:///modules/base/puppet/puppet-enabled',
    }

    motd::script { 'last-puppet-run':
        ensure   => present,
        priority => 97,
        source   => 'puppet:///modules/base/puppet/97-last-puppet-run',
    }
}
