require File.expand_path("../../spec_helper", __FILE__)

describe Ripple::Document::Indexing do
  before :all do
    Object.module_eval do
      class Box
        include Ripple::Document
      end
    end
  end

  before :each do
    @box = Box.new
  end

  it "generates pluralized downcased class name" do
    Box.plural_name.should == "boxes"
  end

  it "allows specification of which attributes to index" do
    Box.indexed_attributes.should_receive(:<<).with(:field)
    Box.index(:field)
  end

  it "stores which attributes have been specificed as indexed" do
    Box.index(:field)
    Box.indexed_attributes.should == [:field]
  end

  it "generates an index bucket name based on its class and an attribute" do
    Box.stub!(:plural_name).and_return("boxes")
    @box.index_bucket_name(:field).should == "boxes_by_field"
  end

  it "stores the robject" do
    robject = mock
    robject.should_receive(:store)
    @box.stub!(:robject).and_return(robject)
    @box.robject_store
  end

  it "returns the robject's links" do
    robject = mock
    robject.should_receive(:links).and_return("links")
    @box.stub!(:robject).and_return(robject)
    @box.robject_links.should == "links"
  end

  it "creates a link to the robject" do
    robject = mock
    robject.should_receive(:to_link).with("rel").and_return("link")
    @box.stub!(:robject).and_return(robject)
    @box.robject_to_link("rel").should == "link"
  end
end

describe Ripple::Document::Index do
  before do
    @document = stub("document", :null_object => true)
    @attribute = :field
    @index = Ripple::Document::Index.new(@document, @attribute)
  end

  it "delegates class method find to new" do
    Ripple::Document::Index.should_receive(:new).with(@document, @attribute).and_return("new")
    Ripple::Document::Index.find(@document, @attribute).should == "new"
  end

  it "has a document" do
    @index.should respond_to(:document)
    @index.document.should == @document
  end

  it "has an attribute" do
    @index.should respond_to(:attribute)
    @index.attribute.should == @attribute
  end

  it "gets the link from the document to itself" do
    @document.should_receive(:link_to_index).with(@attribute).and_return("link_to_index")
    @index.link_to_index.should == "link_to_index"
  end

  it "knows if it can find a link from the document to itself" do
    @index.should_receive(:link_to_index).and_return("link_to_index")
    @index.link_to_index?.should be_true
  end

  it "knows if it can't find a link from the document to itself" do
    @index.should_receive(:link_to_index).and_return(nil)
    @index.link_to_index?.should be_false
  end

  it "gets the bucket that the index robject is in" do
    link_to_index = stub(:bucket => "index_bucket_name")
    @index.stub!(:link_to_index).and_return(link_to_index)
    Ripple.client.should_receive(:[]).with("index_bucket_name").and_return("index_bucket")
    @index.index_bucket.should == "index_bucket"
  end

  it "gets the index robject" do
    link_to_index = stub(:key => 1)
    @index.stub!(:link_to_index).and_return(link_to_index)
    index_bucket = mock
    index_bucket.should_receive(:[]).with(1).and_return("index_robject")
    @index.stub!(:index_bucket).and_return(index_bucket)
    @index.index_robject.should
  end

  it "knows if it can find a link to the document" do
    @index.stub!(:link_to_document).and_return(nil)
    @index.link_to_document?.should be_false
  end

  it "is linked if a link to the document and a link to the index exist" do
    @index.stub!(:link_to_document?).and_return(true)
    @index.stub!(:link_to_index?).and_return(true)
    @index.linked?.should be_true
  end

  it "is not linked if a link to the document does not exist" do
    @index.stub!(:link_to_document?).and_return(false)
    @index.stub!(:link_to_index?).and_return(true)
    @index.linked?.should be_false
  end

  it "is not linked if a link to the index does not exist" do
    @index.stub!(:link_to_document?).and_return(true)
    @index.stub!(:link_to_index?).and_return(false)
    @index.linked?.should be_false
  end

  it "knows the attribute value" do
    document = stub(:attributes => {:name => "bob"})
    @index.stub!(:document).and_return(document)
    @index.stub!(:attribute).and_return(:name)
    @index.attribute_value.should == "bob"
  end

  it "is stale if it is not linked and the attribute value has changed" do
    @index.stub!(:linked?).and_return(false)
    @index.stub!(:attribute_value_changed?).and_return(true)
    @index.stale?.should be_true
  end

  it "is stale if it is not linked and the attribute value hasnt changed" do
    @index.stub!(:linked?).and_return(false)
    @index.stub!(:attribute_value_changed?).and_return(false)
    @index.stale?.should be_true
  end

  it "is stale if it is linked and the attribute value has changed" do
    @index.stub!(:linked?).and_return(true)
    @index.stub!(:attribute_value_changed?).and_return(true)
    @index.stale?.should be_true
  end

  it "is not stale if it is linked and the attribute value has not changed" do
    @index.stub!(:linked?).and_return(true)
    @index.stub!(:attribute_value_changed?).and_return(false)
    @index.stale?.should be_false
  end

  it "should delete link and store on refresh if stale" do
    @index.stub!(:stale?).and_return(true)
    @index.should_receive(:delete).ordered
    @index.should_receive(:link).ordered
    @index.should_receive(:store).ordered
    @index.refresh
  end

  it "should do nothing on refresh if not stale" do
    @index.stub!(:stale?).and_return(false)
    @index.should_not_receive(:delete)
    @index.should_not_receive(:link)
    @index.should_not_receive(:store)
    @index.refresh
  end

  it "deletes the link to the document on delete" do
    # expect deletion of link to document
    @index.stub!(:link_to_document).and_return("link_to_document")
    links = mock
    links.should_receive(:delete).with("link_to_document")
    @index.stub!(:index_robject_links).and_return(links)

    # stub out deletion of link to index
    document_robject_links = stub("document_robject_links", :null_object => true)
    @index.stub!(:document_robject_links).and_return(document_robject_links)
    @index.stub!(:link_to_index)

    @index.delete
  end

  it "deletes the link to the index on delete" do
    # expect deletion of link to index
    @index.stub!(:link_to_index).and_return("link_to_index")
    links = mock
    links.should_receive(:delete).with("link_to_index")
    @index.stub!(:document_robject_links).and_return(links)

    # stub out deletion of link to document
    index_robject_links = stub("index_robject_links", :null_object => true)
    @index.stub!(:index_robject_links).and_return(index_robject_links)
    @index.stub!(:link_to_document)

    @index.delete
  end

  it "stores the index robject" do
    index_robject = mock
    index_robject.should_receive(:store)
    @index.stub!(:index_robject).and_return(index_robject)
    @index.store
  end

  it "stores the document robject" do
    @document.should_receive(:robject_store)
    index_robject = stub("index_robject", :null_object => true)
    @index.stub!(:index_robject).and_return(index_robject)
    @index.store
  end

  it "generates a relation name for the links" do
    @index.stub!(:plural_model_name).and_return("models")
    @index.relation.should == "models_by_field_index"
  end

  it "has a shothand to the document robject links" do
    @document.stub!(:robject_links).and_return("robject_links")
    @index.document_robject_links.should == "robject_links"
  end

  it "has a shothand to the index robject links" do
    index_robject = stub(:links => "robject_links")
    @index.stub!(:index_robject).and_return(index_robject)
    @index.index_robject_links.should == "robject_links"
  end

  it "delegates plural model name to the documents class" do
    klass = stub
    klass.stub!(:plural_name).and_return("models")
    @document.stub!(:class).and_return(klass)
    @index.plural_model_name.should == "models"
  end

  it "knows when the attribute value has changed" do
    link_to_index = stub(:key => "marmite+and+toast")
    @index.stub!(:link_to_index).and_return(link_to_index)
    @index.stub!(:attribute_value).and_return("toast and butter")
    @index.attribute_value_changed?.should be_true
  end

  it "knows when the attribute value has not changed" do
    link_to_index = stub(:key => "marmite+and+toast")
    @index.stub!(:link_to_index).and_return(link_to_index)
    @index.stub!(:attribute_value).and_return("marmite and toast")
    @index.attribute_value_changed?.should be_false
  end

  it "links the index to the document" do
    @index.stub!(:document_robject_to_link).and_return("document_robject_to_link")
    index_robject_links = mock
    index_robject_links.should_receive(:<<).with("document_robject_to_link")
    @index.stub!(:index_robject_links).and_return(index_robject_links)

    @index.stub!(:index_robject_to_link)

    @index.link
  end

  it "links the document to the index" do
    @index.stub!(:index_robject_to_link).and_return("index_robject_to_link")
    document_robject_links = mock
    document_robject_links.should_receive(:<<).with("index_robject_to_link")
    @index.stub!(:document_robject_links).and_return(document_robject_links)

    index_robject_links = stub("index_robject_links", :null_object => true)
    @index.stub!(:index_robject_links).and_return(index_robject_links)
    @index.stub!(:document_robject_to_link)

    @index.link
  end

  it "generates a link to the document robject" do
    @index.stub!(:relation).and_return("relation")
    @document.should_receive(:robject_to_link).with("relation").and_return("document_robject_to_link")
    @index.document_robject_to_link.should == "document_robject_to_link"
  end

  it "generates a link to the index robject" do
    @index.stub!(:relation).and_return("relation")
    index_robject = mock
    index_robject.should_receive(:to_link).with("relation").and_return("index_robject_to_link")
    @index.should_receive(:index_robject).and_return(index_robject)
    @index.index_robject_to_link.should == "index_robject_to_link"
  end
end