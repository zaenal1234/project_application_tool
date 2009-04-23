require File.dirname(__FILE__) + '/../spec_helper'

describe CostItemsController do

  before do 
    session[:cas_sent_to_gateway] = true # make cas think it's already gone to the server to avoid redirect
    @viewer = mock_model(Viewer, :id => 1, :viewer_userID => "copter", :viewer_passWord => "9cdfb439c7876e703e307864c9167a15",
                        :viewer_isActive= => 1, :viewer_lastLogin= => Time.now, :save! =>'', :person =>'', :is_student? => false)
    Viewer.stub!(:find).and_return(@viewer)
    @event_group = mock_model(EventGroup, :id => 1, :title => '', :empty? => false, :logo => "a", :projects=>[], :prep_items =>[])
    EventGroup.stub!(:find).and_return(@event_group)
    @project = mock_model(Project, :id => 1, :find_all_by_hidden => [@project], :collect =>[])
    Project.stub!(:find).and_return(@project)
    @event_group.stub!(:projects).and_return(@project)
    session[:user_id] = @viewer.id
    session[:event_group_id]=1
    
    @cost_item = mock_model(CostItem, :id => 1, :description => '', :type => '', :amount => 1, :optional => true )
    CostItem.stub!(:find).and_return(@cost_item)
    CostItem.stub!(:project).and_return(@project)
    
  end

  describe "vaild cost item spec" do
    
    it "should create new cost item" do
      post 'create', :cost_item =>@params
      assigns[:cost_item].should_not be_new_record
      flash[:error].should be_nil
      flash[:notice].should_not be_nil
    end
        
    it "should update cost item" do
      post 'update', :cost_item => @params
      response.should be_success
    end
    
    it "should destroy cost item" do
      CostItem.delete_all
      response.should be_success
    end
    
  end
  
  describe "invalid cost item spec" do
  end
  
end