# This class contains production-specific performance hacks
# These should have zero functional effect, they are merely system-level
# tweaks to support heavy load/traffic.
class role::cache::perf {
    include cpufrequtils # defaults to "performance"

    # This seems to prevent long term memory fragmentation issues that
    #  can cause VM perf issues.  This seems to be less necessary on jessie
    #  with other assorted fixes in place, and we could experiment with
    #  removing it entirely at a later time when things are more stable.
    #  (watch for small but increasing sys% spikes on upload caches if so,
    #  may take days to have real effect).
    cron { 'varnish_vm_compact_cron':
        command => 'echo 1 >/proc/sys/vm/compact_memory',
        user    => 'root',
        minute  => '*',
    }

    # Bump min_free_kbytes to ensure network buffers are available quickly
    #   without having to evict cache on the spot
    vm::min_free_kbytes { 'cache':
        pct => 2,
        min => 131072,
        max => 1048576,
    }

    # RPS/RSS to spread network i/o evenly
    interface::rps { 'eth0': }

    # flush vm more steadily in the background. helps avoid large performance
    #   spikes related to flushing out disk write cache.
    sysctl::parameters { 'cache_role_vm_settings':
        values => {
            'vm.dirty_ratio'            => 40,  # default 20
            'vm.dirty_background_ratio' => 5,   # default 10
            'vm.dirty_expire_centisecs' => 500, # default 3000
        },
    }

    # Extended notes/docs on network tunables below
    # ---
    # tcp_slow_start_after_idle: SSR resets the congestion window of
    # connections that have gone idle, which means it has a tendency to reset
    # the congestion window of HTTP keepalive and HTTP/2 connections, which are
    # characterized by short bursts of activity separated by long idle times.
    # ---
    # tcp_tw_(reuse|recycle): both are off by default
    # cf. http://vincent.bernat.im/en/blog/2014-tcp-time-wait-state-linux.html
    #    _recycle is dangerous: it violates RFCs, and probably breaks clients
    # when many clients are behind a single NAT gateway, and affects the
    # recycling of TIME_WAIT slots for both incoming and outgoing connections.
    #    _reuse is not-so-dangerous: it only affects outgoing connections, and
    # looks at timestamp and other state information to gaurantee that the
    # reuse doesn't cause issues within reasonable constraints.
    #    This helps prevent TIME_WAIT issues for our $localip<->$localip
    # connections from nginx to varnish-fe:80 - some of our caches reach
    # connection volume/rate spikes where this is a real issue.  Without this
    # setting, turning on keepalives for nginx->varnish tends to cause 502 Bad
    # Gateway spikes (whereas without keepalives, clients were being delayed or
    # queued slightly waiting indirectly on the TIME_WAIT slots).
    #    There may be better solutions for this problem in the big picture -
    # like balancing nginx->varnish local traffic across several local
    # listening ports for varnish-fe, or using unix domain sockets for these
    # connections and avoiding IP entirely (if varnishd supported them).  Or of
    # course implementing decent HTTPS support directly in varnish :P
    # ---
    # tcp_notsent_lowat:
    # Default is -1 (unset).  Setting this changes TCP sockets' writeability
    # behavior.  The default behavior is to keep the socket writeable until the
    # whole socket buffer fills.  With this set, even if there's buffer space,
    # the kernel doesn't notify of writeability (e.g. via epoll()) until the
    # amount of unsent data (as opposed to unacked) in the socket buffer is
    # less than this value.  This reduces local buffer bloat on our server's
    # sending side, which may help with HTTP/2 prioritization.  The magic value
    # for tuning is debateable, but arguably even setting a conservative
    # (higher) value here is better than not setting it all, in almost all
    # cases for any kind of TCP traffic.  ~128K seems to be a common
    # recommendation for something close-ish to optimal for internet-facing
    # things.
    # ---

    # Network tuning for high-load HTTP caches
    sysctl::parameters { 'cache proxy network tuning':
        values => {
            # Increase the number of ephemeral ports
            'net.ipv4.ip_local_port_range'       => [ 1024, 65535 ],

            # All prod caches are 10GbE, standard recommendation is 300K for 10G
            # and 30K for 1G.  Our inbound traffic max is closer to 1G levels,
            # since we have 10G LVS splitting traffic to ~8 or more hosts for
            # high-traffic clusters.  Still, we should double the 1GbE numbers
            # at least, just in case of bursts and inequality, etc.  If low,
            # will see drops in col 2 of /proc/net/softnet_stat
            'net.core.netdev_max_backlog'        => 60000,

            # Default:1 - setting this to zero defers timestamping until after
            # RPS.  It's more efficient this way, but timestamp doesn't account
            # for any tiny delays in queueing before RPS, which I don't think is
            # an issue in our case.
            'net.core.netdev_tstamp_prequeue'    => 0,

            # Our rate of incoming SYN on heaviest cp hosts peaks around
            # 1-2K/sec.  For somaxconn, the SYN numbers should be multiplied
            # out for a few seconds of headroom (bursts, and userspace delays)
            # and then perhaps doubled again to handle the influx of depooling
            # large datacenters.  Note somaxconn is just a parameter limit, the
            # application still needs to set this explicitly (within the
            # limit).
            'net.core.somaxconn'                 => 16384,

            # Our active connection concurrency peaks in the ~100K-200K range
            # per cp host (e.g. text esams as shown in ipvsadm).  For
            # max_syn_backlog, we probably want a small multiple of peak
            # concurrency (maybe even just ~1x), as well as (again) dc failover
            # and/or cp host depool headroom.
            'net.ipv4.tcp_max_syn_backlog'       => 524288,

            # Building on the metrics above - tw_buckets should be somewhere
            # close to the concurrency/syn_backlog sort of level as well so that
            # we properly timewait connections when necc.  Note that tw_reuse
            # moderates the localhost<->localhost timewaits.  max_orphans should
            # be close to the same value, I think, as most of the lingering TW
            # will be orphans.
            'net.ipv4.tcp_max_tw_buckets'        => 524288,
            'net.ipv4.tcp_max_orphans'           => 524288,
            'net.ipv4.tcp_tw_reuse'              => 1, # documented above

            # FIN_WAIT_2 orphan time, def 60.  Reducing this reduces wasted
            # sockets and memory, and there's no good reason to set it higher
            # than roughly the maximum reasonable client RTT in our case.
            'net.ipv4.tcp_fin_timeout'           => 3,

            # Defaults are synack:5 and syn:6.  These control retries on SYN
            # (outbound) and SYNACK (inbound) before giving up on connection
            # establishment.  The defaults with the normal backoff timers can
            # leave not-yet-connected sockets lingering for unacceptably-long
            # times (1-2 minutes).  Aside from waste, that's also a potential
            # DoS vector we'd rather not have.  The "2" value drops the maximum
            # time windows down to ~7 seconds.
            'net.ipv4.tcp_synack_retries'        => 2,
            'net.ipv4.tcp_syn_retries'           => 2,

            # Pure perf hacks (documented above)
            'net.ipv4.tcp_notsent_lowat'         => 131072,
            'net.ipv4.tcp_slow_start_after_idle' => 0,
        },
    }
}
