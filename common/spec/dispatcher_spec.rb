#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.join(File.dirname(__FILE__), 'spec_helper')

class Foo
  include RightScale::Actor
  expose :bar, :index, :i_kill_you
  on_exception :handle_exception

  def index(payload)
    bar(payload)
  end

  def bar(payload)
    ['hello', payload]
  end
  
  def bar2(payload, deliverable)
    deliverable
  end

  def i_kill_you(payload)
    raise RuntimeError.new('I kill you!')
  end

  def handle_exception(method, deliverable, error)
  end
end

class Bar
  include RightScale::Actor
  expose :i_kill_you
  on_exception do |method, deliverable, error|
    @scope = self
    @called_with = [method, deliverable, error]
  end

  def i_kill_you(payload)
    raise RuntimeError.new('I kill you!')
  end
end

# No specs, simply ensures multiple methods for assigning on_exception callback,
# on_exception raises exception when called with an invalid argument.
class Doomed
  include RightScale::Actor
  on_exception do
  end
  on_exception lambda {}
  on_exception :doh
end

# Mock the EventMachine deferrer.
class EMMock
  def self.defer(op = nil, callback = nil)
    callback.call(op.call)
  end
end

# Mock the EventMachine deferrer but do not do callback.
class EMMockNoCallback
  def self.defer(op = nil, callback = nil)
    op.call
  end
end

describe "RightScale::Dispatcher" do

  include FlexMock::ArgumentTypes

  before(:each) do
    flexmock(RightScale::RightLinkLog).should_receive(:info).by_default
    flexmock(RightScale::RightLinkLog).should_receive(:error).by_default
    @broker = flexmock("Broker", :subscribe => true, :publish => true).by_default
    @actor = Foo.new
    @registry = RightScale::ActorRegistry.new
    @registry.register(@actor, nil)
    @agent = flexmock("Agent", :identity => "agent", :broker => @broker, :registry => @registry, :options => {}).by_default
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
  end

  it "should dispatch a request" do
    req = RightScale::Request.new('/foo/bar', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should dispatch the deliverable to actions that accept it" do
    req = RightScale::Request.new('/foo/bar2', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == req
  end
  
  it "should dispatch a request to the default action" do
    req = RightScale::Request.new('/foo', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should handle custom prefixes" do
    @registry.register(Foo.new, 'umbongo')
    req = RightScale::Request.new('/umbongo/bar', 'you')
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should call the on_exception callback if something goes wrong" do
    req = RightScale::Request.new('/foo/i_kill_you', nil)
    flexmock(@actor).should_receive(:handle_exception).with(:i_kill_you, req, Exception).once
    @dispatcher.dispatch(req)
  end

  it "should call on_exception Procs defined in a subclass with the correct arguments" do
    actor = Bar.new
    @registry.register(actor, nil)
    req = RightScale::Request.new('/bar/i_kill_you', nil)
    @dispatcher.dispatch(req)
    called_with = actor.instance_variable_get("@called_with")
    called_with[0].should == :i_kill_you
    called_with[1].should == req
    called_with[2].should be_kind_of(RuntimeError)
    called_with[2].message.should == 'I kill you!'
  end

  it "should call on_exception Procs defined in a subclass in the scope of the actor" do
    actor = Bar.new
    @registry.register(actor, nil)
    req = RightScale::Request.new('/bar/i_kill_you', nil)
    @dispatcher.dispatch(req)
    actor.instance_variable_get("@scope").should == actor
  end

  it "should log error if something goes wrong" do
    RightScale::RightLinkLog.should_receive(:error).once
    req = RightScale::Request.new('/foo/i_kill_you', nil)
    @dispatcher.dispatch(req)
  end

  it "should reject requests that are stale" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT STALE/})
    @agent.should_receive(:options).and_return(:fresh_timeout => 15)
    @agent.should_receive(:advertise_services).once
    @broker.should_receive(:publish).never
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Push.new('/foo/bar', 'you', :created_at => (Time.now.to_f - 16))
    @dispatcher.dispatch(req).should == nil
  end

  it "should report stale requests to mapper if have reply_to" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT STALE/})
    @agent.should_receive(:options).and_return(:fresh_timeout => 15)
    @agent.should_receive(:advertise_services).once
    @broker.should_receive(:publish).once
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :created_at => (Time.now.to_f - 16))
    @dispatcher.dispatch(req).should == nil
  end

  it "should advertise services if has not done so recently" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).twice.with(on {|arg| arg =~ /REJECT STALE/})
    @agent.should_receive(:options).and_return(:fresh_timeout => 15)
    @agent.should_receive(:advertise_services).once
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Push.new('/foo/bar', 'you', :created_at => (Time.now.to_f - 16))
    @dispatcher.dispatch(req).should == nil
    @dispatcher.dispatch(req).should == nil
  end

  it "should not reject requests that are fresh" do
    @agent.should_receive(:options).and_return(:fresh_timeout => 15)
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :created_at => (Time.now.to_f - 14))
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should not check age of requests if no fresh_timeout" do
    @agent.should_receive(:options).and_return(:fresh_timeout => nil)
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :created_at => (Time.now.to_f - 15))
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should not check age of requests with created_at value of 0" do
    @agent.should_receive(:options).and_return(:fresh_timeout => 15)
    @dispatcher = RightScale::Dispatcher.new(@agent)
    @dispatcher.em = EMMock
    req = RightScale::Request.new('/foo/bar', 'you', :created_at => 0)
    res = @dispatcher.dispatch(req)
    res.should(be_kind_of(RightScale::Result))
    res.token.should == req.token
    res.results.should == ['hello', 'you']
  end

  it "should reject duplicate requests" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT DUP/})
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      @dispatcher.completed[req.token] = Time.now.to_i
      @dispatcher.dispatch(req).should == nil
      EM.stop
    end
  end

  it "should reject duplicate retry requests" do
    flexmock(RightScale::RightLinkLog).should_receive(:info).once.with(on {|arg| arg =~ /REJECT RETRY DUP/})
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.completed["try2"] = Time.now.to_i
      @dispatcher.dispatch(req).should == nil
      EM.stop
    end
  end

  it "should not reject non-duplicate requests" do
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.completed["try3"] = Time.now.to_i
      @dispatcher.dispatch(req).should_not == nil
      EM.stop
    end
  end

  it "should not check for duplicates if dup_check disabled" do
    EM.run do
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      req.tries.concat(["try1", "try2"])
      @dispatcher.completed["try2"] = Time.now.to_i
      @dispatcher.dispatch(req).should_not == nil
      EM.stop
    end
  end

  it "should remove old completed requests when timeout" do
    EM.run do
      @agent.should_receive(:options).and_return(:dup_check => true, :fresh_timeout => 0.4, :completed_interval => 0.2)
      @dispatcher = RightScale::Dispatcher.new(@agent)
      req = RightScale::Request.new('/foo/bar', 'you', :token => "try")
      @dispatcher.dispatch(req).should_not == nil
      EM.add_timer(0.1) do
        @dispatcher.completed.should_not == {}
      end
      EM.add_timer(1.5) do
        @dispatcher.completed.should == {}
        EM.stop
      end
    end
  end

  it "should return dispatch age of youngest unfinished request" do
    @dispatcher.em = EMMockNoCallback
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Push.new('/foo/bar', 'you'))
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
    @dispatcher.dispatch_age.should == 100
  end

  it "should return dispatch age of nil if all requests finished" do
    flexmock(Time).should_receive(:now).and_return(Time.at(1000000)).by_default
    @dispatcher.dispatch_age.should be_nil
    @dispatcher.dispatch(RightScale::Request.new('/foo/bar', 'you'))
    flexmock(Time).should_receive(:now).and_return(Time.at(1000100))
    @dispatcher.dispatch_age.should == nil
  end

end # RightScale::Dispatcher