class profile::idp(
    Hash                $ldap_config            = lookup('ldap', Hash, hash, {}),
    String              $keystore_password      = lookup('profile::idp::keystore_password'),
    String              $key_password           = lookup('profile::idp::key_password'),
    String              $tgc_signing_key        = lookup('profile::idp::tgc_signing_key'),
    String              $tgc_encryption_key     = lookup('profile::idp::tgc_encryption_key'),
    String              $webflow_signing_key    = lookup('profile::idp::webflow_signing_key'),
    String              $webflow_encryption_key = lookup('profile::idp::webflow_encryption_key'),
    String              $u2f_signing_key        = lookup('profile::idp::u2f_signing_key'),
    String              $u2f_encryption_key     = lookup('profile::idp::u2f_encryption_key'),
    String              $totp_signing_key       = lookup('profile::idp::totp_signing_key'),
    String              $totp_encryption_key    = lookup('profile::idp::totp_encryption_key'),
    Integer             $max_session_length     = lookup('profile::idp::max_session_length'),
    Hash[String,Hash]   $services               = lookup('profile::idp::services'),
    Array[String[1]]    $ldap_attribute_list    = lookup('profile::idp::ldap_attributes'),
    Stdlib::Fqdn        $idp_primary            = lookup('profile::idp::idp_primary'),
    Stdlib::Fqdn        $idp_failover           = lookup('profile::idp::idp_failover'),
    Array[String]       $actuators              = lookup('profile::idp::actuators'),
    Array[Stdlib::Host] $prometheus_nodes       = lookup('prometheus_nodes')
){

    include passwords::ldap::production
    class{ 'sslcert::dhparam': }
    include profile::tlsproxy::envoy

    ferm::service {'cas-https':
        proto => 'tcp',
        port  => 443,
    }

    class { 'rsync::server':
        wrap_with_stunnel => true,
    }

    backup::set { 'idp': }

    $jmx_port = 9200
    $jmx_config = '/etc/prometheus/cas_jmx_exporter.yaml'
    $jmx_jar = '/usr/share/java/prometheus/jmx_prometheus_javaagent.jar'
    $java_opts = "-javaagent:${jmx_jar}=${facts['networking']['ip']}:${jmx_port}:${jmx_config}"
    $groovy_source = 'puppet:///modules/profile/idp/global_principal_attribute_predicate.groovy'
    class { 'apereo_cas':
        server_name            => 'https://idp.wikimedia.org',
        server_prefix          => '/',
        server_port            => 8080,
        server_enable_ssl      => false,
        tomcat_proxy           => true,
        groovy_source          => $groovy_source,
        prometheus_nodes       => $prometheus_nodes,
        keystore_content       => secret('casserver/thekeystore'),
        keystore_password      => $keystore_password,
        key_password           => $key_password,
        tgc_signing_key        => $tgc_signing_key,
        tgc_encryption_key     => $tgc_encryption_key,
        webflow_signing_key    => $webflow_signing_key,
        webflow_encryption_key => $webflow_encryption_key,
        u2f_signing_key        => $u2f_signing_key,
        u2f_encryption_key     => $u2f_encryption_key,
        totp_signing_key       => $totp_signing_key,
        totp_encryption_key    => $totp_encryption_key,
        ldap_start_tls         => false,
        ldap_uris              => ["ldaps://${ldap_config[ro-server]}:636",
                                    "ldaps://${ldap_config[ro-server-fallback]}:636",],
        ldap_base_dn           => $ldap_config['base-dn'],
        ldap_attribute_list    => $ldap_attribute_list,
        log_level              => 'DEBUG',
        ldap_bind_pass         => $passwords::ldap::production::proxypass,
        ldap_bind_dn           => "cn=proxyagent,ou=profile,${ldap_config['base-dn']}",
        services               => $services,
        idp_primary            => $idp_primary,
        idp_failover           => $idp_failover,
        java_opts              => $java_opts,
        max_session_length     => $max_session_length,
        actuators              => $actuators,
    }
    profile::prometheus::jmx_exporter{ "idp_${facts['networking']['hostname']}":
        hostname         => $facts['networking']['hostname'],
        port             => $jmx_port,
        prometheus_nodes => $prometheus_nodes,
        config_dir       => $jmx_config.dirname,
        config_file      => $jmx_config,
        content          => file('profile/idp/cas_jmx_exporter.yaml'),
    }

}
