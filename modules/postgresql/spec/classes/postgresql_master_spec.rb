require 'spec_helper'

describe 'postgresql::master', :type => :class do
    let(:facts) do
      {
        'lsbdistcodename' => 'jessie',
        'lsbdistrelease' => '8.6',
        'lsbdistid' => 'Debian'
      }
    end

    let(:params) { {
        :ensure           => 'present',
        :master_server    => 'test',
        }
    }

    context 'ensure present' do
        it { should contain_class('postgresql::server') }
        it do
            should contain_file('/etc/postgresql/9.4/main/postgresql.conf')
                .with_ensure('present')
                .with_content(/include 'master.conf'/)
        end
        it do
            should contain_file('/etc/postgresql/9.4/main/master.conf')
                .with_ensure('present')
                .with_content(/max_wal_senders = 5/)
                .with_content(/checkpoint_segments = 64/)
                .with_content(/wal_keep_segments = 128/)
        end
    end
end

describe 'postgresql::master', :type => :class do
    let(:facts) do
      {
        'lsbdistcodename' => 'jessie',
        'lsbdistrelease' => '8.6',
        'lsbdistid' => 'Debian'
      }
    end

    let(:params) { {
        :ensure           => 'absent',
        :master_server    => 'test',
        }
    }

    context 'ensure absent' do
        it { should contain_class('postgresql::server') }
        it { should contain_file('/etc/postgresql/9.4/main/postgresql.conf').with_ensure('absent') }
        it { should contain_file('/etc/postgresql/9.4/main/master.conf').with_ensure('absent') }
    end
end
