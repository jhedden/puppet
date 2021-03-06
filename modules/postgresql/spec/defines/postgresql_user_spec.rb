require 'spec_helper'

describe 'postgresql::user', :type => :define do
    let(:title) { 'something@host.example.com' }
    let(:params) { {
        :user     => 'something',
        :password => 'soemthing',
        :ensure   => 'present',
    } }
    let(:facts) do
      {
        'lsbdistcodename' => 'jessie',
        'lsbdistrelease' => '8.6',
        'lsbdistid' => 'Debian'
      }
    end
    let(:pre_condition) { 'include postgresql::server' }

    context 'with ensure present' do
        it { should contain_exec('create_user-something@host.example.com') }
        it { should contain_exec('pass_set-something@host.example.com') }
        it { should contain_augeas('hba_create-something@host.example.com') }
    end
end

describe 'postgresql::user', :type => :define do
    let(:title) { 'something@host.example.com' }
    let(:params) { {
        :user     => 'something',
        :password => 'soemthing',
        :ensure   => 'absent',
    } }
    let(:facts) do
      {
        'lsbdistcodename' => 'jessie',
        'lsbdistrelease' => '8.6',
        'lsbdistid' => 'Debian'
      }
    end
    let(:pre_condition) { 'include postgresql::server' }

    context 'with ensure absent' do
    it { should contain_exec('drop_user-something@host.example.com') }
    it { should contain_augeas('hba_drop-something@host.example.com') }
    end
end
