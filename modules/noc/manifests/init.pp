# https://noc.wikimedia.org/
class noc {

    include ::apache

    $ssl_settings = ssl_ciphersuite('apache-2.2', 'compat')

    apache::site { 'noc.wikimedia.org':
        content => template('noc/noc.wikimedia.org.erb'),
    }

    include ::apache::mod::php5
    include ::apache::mod::userdir
    include ::apache::mod::cgi
    include ::apache::mod::ssl

    # dbtree config
    include passwords::tendril
    $tendril_user_web = $passwords::tendril::db_user_web
    $tendril_pass_web = $passwords::tendril::db_pass_web

    file { '/srv/mediawiki/docroot/noc/dbtree':
        ensure => 'directory',
        owner  => 'mwdeploy',
        group  => 'mwdeploy',
    }

    git::clone { 'operations/software/dbtree':
        directory => '/srv/mediawiki/docroot/noc/dbtree',
        branch    => 'master',
        owner     => 'mwdeploy',
        group     => 'mwdeploy',
        require   => File['/srv/mediawiki/docroot/noc/dbtree'],
    }

    file { '/srv/mediawiki/docroot/noc/dbtree/inc/config.php':
        ensure  => 'present',
        owner   => 'mwdeploy',
        group   => 'mwdeploy',
        content => template('noc/dbtree.config.php.erb'),
    }

    # Monitoring
    monitoring::service { 'http-noc':
        description   => 'HTTP-noc',
        check_command => 'check_http_url!noc.wikimedia.org!http://noc.wikimedia.org'
    }

}

