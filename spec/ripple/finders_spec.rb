# Copyright 2010 Sean Cribbs, Sonian Inc., and Basho Technologies, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
require File.expand_path("../../spec_helper", __FILE__)

describe Ripple::Document::Finders do
  before :all do
    Object.module_eval do
      class Box
        include Ripple::Document
        property :shape, String
      end
    end
  end

  before :each do
    @http = mock("HTTP Backend")
    @client = Ripple.client
    @client.stub!(:http).and_return(@http)
    @bucket = Riak::Bucket.new(@client, "boxes")
    @client.stub!(:[]).and_return(@bucket)
  end

  it "should return an empty array if no keys are passed to find" do
    Box.find().should be_nil
  end
  
  it "should raise Ripple::DocumentNotFound if an empty array is passed to find!" do
    lambda { Box.find!() }.should raise_exception(Ripple::DocumentNotFound, "Couldn't find document without a key")
  end

  it "should determine the attribute name" do
    Box.match_attribute_name(:find_by_attribute_name).should == :attribute_name
  end

  it "should return nil if it cannot determine the attribute name" do
    Box.match_attribute_name(:random_junk).should == nil
  end

  it "should find robjects by indexed attribute" do
    Box.should_receive(:robjects_by_indexed_attribute).with(:field, "value").and_return([])
    Box.find_by_indexed_attribute(:field, "value")
  end

  it "should collect instantiated robjects" do
    robject = stub
    Box.stub!(:robjects_by_indexed_attribute).and_return([robject])
    Box.should_receive(:instantiate).with(robject).and_return("instantiated_robject")
    Box.find_by_indexed_attribute(:field, "value").should == ["instantiated_robject"]
  end

  describe "finding single documents" do
    it "should find a single document by key and assign its attributes" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      box = Box.find("square")
      box.should be_kind_of(Box)
      box.shape.should == "square"
      box.key.should == "square"
      box.instance_variable_get(:@robject).should_not be_nil
      box.should_not be_new_record
    end
    
    it "should not raise an exception when finding an existing document with find!" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      lambda { Box.find!("square") }.should_not raise_exception(Ripple::DocumentNotFound)
    end
    
    it "should return the document when calling find!" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      box = Box.find!("square")
      box.should be_kind_of(Box)
    end

    it "should return nil when no object exists at that key" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 404, {}, "404 not found"))
      box = Box.find("square")
      box.should be_nil
    end
    
    it "should raise DocumentNotFound when using find! if no object exists at that key" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 404, {}, "404 not found"))
      lambda { Box.find!("square") }.should raise_exception(Ripple::DocumentNotFound, "Couldn't find document with key: square")
    end

    it "should re-raise the failed request exception if not a 404" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 500, {}, "500 internal server error"))
      lambda { Box.find("square") }.should raise_error(Riak::FailedRequest)
    end
    
    it "should handle a key with a nil value" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => nil})
      box = Box.find("square")
      box.should be_kind_of(Box)
      box.key.should == "square"
    end
      
  end

  describe "finding multiple documents" do
    it "should find multiple documents by the keys" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"rectangle"}'})
      boxes = Box.find("square", "rectangle")
      boxes.should have(2).items
      boxes.first.shape.should == "square"
      boxes.last.shape.should == "rectangle"
    end

    describe "when using find with missing keys" do
      before :each do
        @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
        @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 404, {}, "404 not found"))
      end
      
      it "should return nil for documents that no longer exist" do
        boxes = Box.find("square", "rectangle")
        boxes.should have(2).items
        boxes.first.shape.should == "square"
        boxes.last.should be_nil
      end
    
      it "should raise Ripple::DocumentNotFound when calling find! if some of the documents do not exist" do
        lambda { Box.find!("square", "rectangle") }.should raise_exception(Ripple::DocumentNotFound, "Couldn't find documents with keys: rectangle")
      end
    end
  end

  describe "finding all documents in the bucket" do
    it "should load all objects in the bucket" do
      @bucket.should_receive(:keys).and_return(["square", "rectangle"])
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"rectangle"}'})
      boxes = Box.all
      boxes.should have(2).items
      boxes.first.shape.should == "square"
      boxes.last.shape.should == "rectangle"
    end

    it "should exclude objects that are not found" do
      @bucket.should_receive(:keys).and_return(["square", "rectangle"])
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 404, {}, "404 not found"))
      boxes = Box.all
      boxes.should have(1).item
      boxes.first.shape.should == "square"
    end

    it "should yield found objects to the passed block and return an empty array" do
      @bucket.should_receive(:keys).and_yield(["square"]).and_yield(["rectangle"])
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"rectangle"}'})
      @block = mock()
      @block.should_receive(:ping).twice
      Box.all do |box|
        @block.ping
        ["square", "rectangle"].should include(box.shape)
      end.should == []
    end

    it "should yield found objects to the passed block, excluding missing objects, and return an empty array" do
      @bucket.should_receive(:keys).and_yield(["square"]).and_yield(["rectangle"])
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_raise(Riak::FailedRequest.new(:get, 200, 404, {}, "404 not found"))
      @block = mock()
      @block.should_receive(:ping).once
      Box.all do |box|
        @block.ping
        ["square", "rectangle"].should include(box.shape)
      end.should == []
    end
  end

  describe "single-bucket inheritance" do
    before :all do
      Object.module_eval { class CardboardBox < Box; end }
    end

    it "should instantiate as the proper type if defined in the document" do
      @http.should_receive(:get).with(200, "/riak/", "boxes", "square", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"square"}'})
      @http.should_receive(:get).with(200, "/riak/", "boxes", "rectangle", {}, {}).and_return({:code => 200, :headers => {"content-type" => ["application/json"]}, :body => '{"shape":"rectangle", "_type":"CardboardBox"}'})
      boxes = Box.find("square", "rectangle")
      boxes.should have(2).items
      boxes.first.should_not be_kind_of(CardboardBox)
      boxes.last.should be_kind_of(CardboardBox)
    end

    after :all do
      Object.send(:remove_const, :CardboardBox)
    end
  end

  after :all do
    Object.send(:remove_const, :Box)
  end
end
