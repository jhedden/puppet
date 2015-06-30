# == Function: ssl_ciphersuite( string $servercode, string $encryption_type, int $hsts_days )
#
# Outputs the ssl configuration directives for use with either Nginx
# or Apache using our selection of ciphers and SSL options.
#
# === Arguments
#
# Takes three arguments:
#
# - The servercode, or which browser-version combination to
#   support. At the moment only 'apache-2.2', 'apache-2.4' and 'nginx'
#   are supported.
# - The compatibility mode, trades security vs compatibility.
#   Note that due to POODLE, SSLv3 is universally disabled and none of these
#   options are compatible with SSLv3-only clients such as IE6/XP.
#   Current options are:
#   - strong:     PFS required, ECDHE+AES suites only, TLSv1.1+ only.
#                 Only works for fairly modern browsers.  Definitely not
#                 compatible with: Android 2.x, IE8/XP, OpenSSL 0.9.8, Java6.
#   - compat:     Supports most legacy clients, PFS optional, TLSv1.0+ only.
#   - compat-dhe: Upgrades 'compat' to use DHE for PFS with certain older
#                 clients.  Breaks some older/commercial Java6 clients, but
#                 makes things more secure for Android 2 and OpenSSL 0.9.8.
#                 *Critical* - Requires the use of good (non-default, not
#                 weak, 2048-bit+) DH parameters elsewhere in the server
#                 config, which is not enforced by this code.
# - An optional argument, that if non-nil will set HSTS to max-age of
#   N days
#
# Whenever called, this function will output a list of strings that
# can be safely used in your configuration file as the ssl
# configuration part.
#
# == Examples
#
#     ssl_ciphersuite('apache-2.4', 'compat')
#     ssl_ciphersuite('nginx', 'strong')
#
# == License
#
# Author: Giuseppe Lavagetto
# Copyright 2014 Wikimedia Foundation
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
require 'puppet/util/package'

module Puppet::Parser::Functions
  # Basic list chunks, used to construct bigger lists
  basic = {
    # Only modern reasonably-secure browsers have these.
    # They're all forward-secret, and our preference ordering is
    # (higher trumps all lower considerations, if conflict):
    # 1) GCM > CBC
    # 2) AES128 > AES256
    # 3) SHA-2 > SHA-1
    # 4) ECDSA > RSA
    'strong' => [
      '-ALL',
      'ECDHE-ECDSA-AES128-GCM-SHA256',
      'ECDHE-RSA-AES128-GCM-SHA256',
      'ECDHE-ECDSA-AES256-GCM-SHA384',
      'ECDHE-RSA-AES256-GCM-SHA384',
      'ECDHE-ECDSA-AES128-SHA256',
      'ECDHE-RSA-AES128-SHA256',
      'ECDHE-ECDSA-AES128-SHA',
      'ECDHE-RSA-AES128-SHA',
      'ECDHE-ECDSA-AES256-SHA384',
      'ECDHE-RSA-AES256-SHA384',
      'ECDHE-ECDSA-AES256-SHA',
      'ECDHE-RSA-AES256-SHA',
    ],
    # DHE-based forward-secret option to help e.g. Android 2 and OpenSSL 0.9.8
    # Do not use on a server unless you're *sure* it's not using defaulted
    # and/or weak DH parameters!
    'compat-dhe' => [
      'DHE-RSA-AES128-SHA',
    ],
    # not-forward-secret compat for ancient stuff
    # pref rules same as 'strong' where applicable
    'compat' => [
      'AES128-GCM-SHA256',
      'AES256-GCM-SHA384',
      'AES128-SHA256',
      'AES128-SHA',
      'AES256-SHA256',
      'AES256-SHA',
      'CAMELLIA128-SHA',
      'CAMELLIA256-SHA',
      'DES-CBC3-SHA', # Only for IE8/XP at this point, I think
    ],
  }

  # Final lists exposed to callers
  ciphersuites = {
    'strong'     => basic['strong'],
    'compat'     => basic['strong'] + basic['compat'],
    'compat-dhe' => basic['strong'] + basic['compat-dhe'] + basic['compat'],
  }

  newfunction(
              :ssl_ciphersuite,
              :type => :rvalue,
              :doc  => <<-END
Outputs the ssl configuration part of the webserver config.
Function parameters are:
 servercode - either nginx, apache-2.2 or apache-2.4
 encryption_type - strong, compat, or compat-dhe (do not use compat-dhe unless
                   you are sure of what you're doing, read the extended docs
                   in the source of this function!)
 hsts_days  - how many days should the STS header live. If not expressed, HSTS will
              be disabled

Examples:

   ssl_ciphersuite('apache-2.4', 'compat') # Compatible config for apache 2.4
   ssl_ciphersuite('nginx', 'strong', '365') # PFS-only, use HSTS for 365 days
END
              ) do |args|


    if args.length < 2 || args.length > 3
      fail(ArgumentError, 'ssl_ciphersuite() requires at least 2 arguments')
    end

    servercode = args.shift
    case servercode
    when 'apache-2.4' then
      server = 'apache'
      server_version = 24
    when 'apache-2.2' then
      server = 'apache'
      server_version = 22
    when 'nginx' then
      server = 'nginx'
      server_version = nil
    else
      fail(ArgumentError, "ssl_ciphersuite(): unknown server string '#{servercode}'")
    end

    ciphersuite = args.shift
    unless ciphersuites.has_key?(ciphersuite)
      fail(ArgumentError, "ssl_ciphersuite(): unknown ciphersuite '#{ciphersuite}'")
    end

    cipherlist = ciphersuites[ciphersuite].join(":")

    if ciphersuite == 'strong' && server == 'apache' && server_version < 24
      fail(ArgumentError, 'ssl_ciphersuite(): apache 2.2 cannot work in strong PFS mode')
    end
    if args.length == 1
      hsts_days = args.shift.to_i
    else
      hsts_days = nil
    end

    output = []

    if server == 'apache'
      case ciphersuite
      when 'strong' then
        output.push('SSLProtocol all -SSLv2 -SSLv3 -TLSv1')
      else
        output.push('SSLProtocol all -SSLv2 -SSLv3')
      end
      output.push("SSLCipherSuite #{cipherlist}")
      output.push('SSLHonorCipherOrder On')
      unless hsts_days.nil?
        hsts_seconds = hsts_days * 86400
        output.push("Header always set Strict-Transport-Security \"max-age=#{hsts_seconds}\"")
      end
    else
      # nginx
      case ciphersuite
      when 'strong' then
        output.push('ssl_protocols TLSv1.1 TLSv1.2;')
      else
        output.push('ssl_protocols TLSv1 TLSv1.1 TLSv1.2;')
      end
      output.push("ssl_ciphers #{cipherlist};")
      output.push('ssl_prefer_server_ciphers on;')
      unless hsts_days.nil?
        hsts_seconds = hsts_days * 86400
        output.push("add_header Strict-Transport-Security \"max-age=#{hsts_seconds}\";")
      end
    end
    return output
  end
end
