# Class: puppetmaster::scripts
#
# This class installs some puppetmaster server side scripts required for the
# manifests
#
# == Parameters
#
# [*keep_reports_minutes*]
#   Number of minutes to keep older reports for before deleting them.
#   The cron to remove these is run only every 8 hours, however,
#   to prevent excess load on the prod puppetmasters.
class puppetmaster::scripts(
    Integer      $keep_reports_minutes = 960, # 16 hours
    Boolean      $has_puppetdb         = true,
    Stdlib::Host $ca_server            = $facts['fqdn'],
) {
    $servers = hiera('puppetmaster::servers', {})

    file{'/usr/local/bin/puppet-merge':
        ensure  => present,
        owner   => 'root',
        group   => 'root',
        mode    => '0555',
        content => template('puppetmaster/puppet-merge.erb'),
    }
    file{'/usr/local/bin/puppet-merge.py':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
        source => 'puppet:///modules/puppetmaster/puppet-merge.py',
    }

    # export and sanitize facts for puppet compiler
    require_package('python3-requests', 'python3-yaml')
    file {'/usr/local/bin/puppet-facts-export-puppetdb':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
        source => 'puppet:///modules/puppetmaster/puppet-facts-export-puppetdb.py',
    }

    # this performs the same task as puppet-facts-export but can
    #  run on a host without puppetdb.  This is useful because
    #  the cloud puppetmasters don't use puppetdb to preserve
    #  tenant separation
    file {'/usr/local/bin/puppet-facts-export-nodb':
        ensure => present,
        owner  => 'root',
        group  => 'root',
        mode   => '0555',
        source => 'puppet:///modules/puppetmaster/puppet-facts-export-nodb.sh',
    }

    # Link to the appropriate fact exporter, as appropriate
    #  depending on the presence of puppetdb
    $puppet_facts_export = $has_puppetdb ? {
        false   => '/usr/local/bin/puppet-facts-export-nodb',
        default => '/usr/local/bin/puppet-facts-export-puppetdb',
    }
    file { '/usr/local/bin/puppet-facts-export':
        ensure => link,
        target => $puppet_facts_export
    }

    # Clear out older reports
    cron { 'removeoldreports':
        ensure  => present,
        command => "find /var/lib/puppet/reports -type f -mmin +${keep_reports_minutes} -delete >/dev/null 2>&1",
        user    => puppet,
        hour    => [0, 8, 16], # Run every 8 hours, to prevent excess load
        minute  => 27, # Run at a time when hopefully no other cron jobs are
    }
}
