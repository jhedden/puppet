class role::wmcs::nfs::secondary {
    system::role { $name:
        description => 'NFS secondary share cluster',
    }

    include ::standard
    include ::profile::base::firewall
    include ::profile::wmcs::nfs::ferm
    include ::profile::wmcs::nfs::secondary
}