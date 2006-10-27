require File.dirname(__FILE__) + '/../test_helper'
require 'milestones_controller'

# Re-raise errors caught by the controller.
class MilestonesController; def rescue_action(e) raise e end; end

class MilestonesControllerTest < Test::Unit::TestCase
  FULL_PAGES = [:index]
  POPUPS = [ :new,:create,:show,:edit,:update ]
  NO_RENDERS = [:delete]
  ALL_ACTIONS = FULL_PAGES + POPUPS + NO_RENDERS + [:milestones_calendar]

  def setup
    Project.destroy_all
    User.destroy_all
    create_common_fixtures :user_one, :project_one, :project_two,
                           :past_milestone1, :past_milestone2,
                           :recent_milestone1, :recent_milestone2,
                           :future_milestone1, :future_milestone2
    @project_one.users << @user_one
    @project_two.users << @user_one
    @controller = MilestonesController.new
    @request = ActionController::TestRequest.new
    @response = ActionController::TestResponse.new
    @request.session[:current_user] = @user_one
  end

  def test_authentication_required
    @request.session[:current_user] = nil
    ALL_ACTIONS.each do |a|
      process a
      assert_redirected_to :controller => 'session', :action => 'login'
      assert session[:return_to]
    end
  end

  def test_index
    get :index, :project_id => @project_one.id
    assert_response :success
    assert_equal 'recent', assigns(:past_milestones)
  end
  
  def test_index_all_past
    get :index, :project_id => @project_one.id, :show_all => '1'
    assert_response :success
    assert_equal 'all_past', assigns(:past_milestones)
  end

  def test_no_project_id
    (FULL_PAGES + NO_RENDERS).each do |a|
      process a
      assert_redirected_to :controller => 'error', :action => 'index'
      assert_equal "You attempted to access a view that requires a project to " +
                   "be selected, but no project id was set in your request.",
                   flash[:error]
    end
    POPUPS.each do |a|
      process a
      assert_redirected_to :controller => 'error', :action => 'popup'
      assert_equal "You attempted to access a view that requires a project to " +
                   "be selected, but no project id was set in your request.",
                   flash[:error]
    end
  end

  def test_new
    get :new, 'project_id' => @project_one.id
    assert_response :success
    assert_template 'new'
    assert_equal @project_one, assigns(:project)
    assert_kind_of Milestone, assigns(:milestone)
    assert assigns(:milestone).new_record?
  end

  def test_create
    before_count = Milestone.count
    post :create, 'project_id' => @project_one.id,
         'milestone' => { 'name' => 'Test Create', 'date' => '2005-12-31' }
    assert_response :success
    assert_template 'layouts/refresh_parent_close_popup'
    assert_equal before_count + 1, Milestone.count
  end

  def test_create_invalid
    before_count = Milestone.count
    post :create, 'project_id' => @project_one.id,
         'milestone' => { 'name' => 'test_create_invalid', 'date' => '' }
    assert_redirected_to :controller => 'milestones', :action => 'new'
    assert_kind_of Milestone, session[:new_milestone]
    assert_equal 'test_create_invalid', session[:new_milestone].name
  end

  def test_edit
    get :edit, 'id' => @future_milestone1.id,
        'project_id' => @future_milestone1.project.id
    assert_response :success
    assert_template 'edit'
    assert_equal @future_milestone1, assigns(:milestone)
  end

  def test_edit_from_invalid
    @request.session[:edit_milestone] = @future_milestone1
    get :edit, 'id' => @future_milestone1.id,
        'project_id' => @future_milestone1.project.id
    assert_response :success
    assert_template 'edit'
    assert_kind_of Milestone, assigns(:milestone)
    assert_equal @future_milestone1.id, assigns(:milestone).id
    assert_nil session[:edit_milestone]
  end

  def test_update
    post :update, 'id' => @future_milestone1.id,
         'project_id' => @future_milestone1.project.id,
         'milestone' => { 'name' => 'Fooooo!' }
    assert_response :success
    assert_template 'layouts/refresh_parent_close_popup'
    m = Milestone.find(@future_milestone1.id)
    assert_equal 'Fooooo!', m.name
    assert flash[:status]
  end

  def test_update_invalid
    post :update, 'id' => @future_milestone1.id,
         'project_id' => @future_milestone1.project.id,
         'milestone' => { 'name' => '' }
    assert_redirected_to :controller => 'milestones', :action => 'edit',
                         :id => @future_milestone1.id,
                         :project_id => @future_milestone1.project.id
    m = Milestone.find(@future_milestone1.id)
    m.name = ''
    assert_equal m, session[:edit_milestone]
  end

  def test_delete
    get :delete, 'project_id' => @project_one.id, 'id' => @future_milestone1.id
    assert_redirected_to :controller => 'milestones', :action => 'index'
    assert flash[:status]
    assert_raise(ActiveRecord::RecordNotFound) {
      Milestone.find(@future_milestone1.id)
    }
  end

  def test_show
    get :show, :id => @future_milestone1.id,
        :project_id => @future_milestone1.project.id
    assert_response :success
    assert_template 'show'
    assert_equal @future_milestone1, assigns(:milestone)
  end

  def test_milestones_calendar_all_projects
    @future_milestone2.project = @project_two
    @future_milestone2.date = Date.today + 13
    @future_milestone2.save
    get :milestones_calendar
    assert_response :success
    assert_template '_milestones_calendar'
    days = empty_milestones_days_array
    days[0][:milestones] << @future_milestone1
    days[13][:milestones] << @future_milestone2
    assert_equal days, assigns(:days)
    assert_equal 'Upcoming Milestones (all projects):',
                 assigns(:calendar_title)
  end

  def test_milestones_calendar_one_project
    p1 = Project.create('name' => 'A Test Project')
    m1 = Milestone.create('name' => 'Milestone One', 'date' => Date.today - 1)
    m2 = Milestone.create('name' => 'Milestone Two', 'date' => Date.today)
    m3 = Milestone.create('name' => 'Milestone Three',
                          'date' => Date.today + 13)
    m4 = Milestone.create('name' => 'Milestone Four',
                          'date' => Date.today + 14)
    p1.milestones << [m1,m2,m3,m4]
    p2 = Project.create('name' => 'Another Test Project')
    m5 = Milestone.create('name' => 'Milestone Five', 'date' => Date.today + 2)
    p2.milestones << m5
    @request.session[:current_user].projects << [p1,p2]
    get :milestones_calendar, 'project_id' => p1.id
    assert_response :success
    assert_template '_milestones_calendar'
    days = empty_milestones_days_array
    days[0][:milestones] << m2
    days[13][:milestones] << m3
    assert_equal days, assigns(:days)
    assert_equal 'Upcoming Milestones:', assigns(:calendar_title)
  end
  
  def test_list_future
    process :list, :project_id => @project_one.id, :include => 'future'
    assert_response :success
    assert_template '_list'
    assert_equal [ @future_milestone1, @future_milestone2 ],
                 assigns(:milestones)
  end
  
  def test_list_recent
    process :list, :project_id => @project_one.id, :include => 'recent'
    assert_response :success
    assert_template '_list'
    assert_equal [ @recent_milestone2, @recent_milestone1 ],
                 assigns(:milestones)
  end
  
  def test_list_all_past
    process :list, :project_id => @project_one.id, :include => 'all_past'
    assert_response :success
    assert_template '_list'
    assert_equal [ @recent_milestone2, @recent_milestone1, @past_milestone2, 
                   @past_milestone1 ], assigns(:milestones)
  end
  
  def test_list_nothing_to_show
    @project_one.milestones.clear
    [ 'future', 'recent', 'all_past' ].each do |type|
      process :list, :project_id => @project_one.id, :include => type
      assert_response :success
      assert_equal '<p>Nothing to show.</p>', @response.body
    end
  end

  private

  def empty_milestones_days_array
    days = []
    14.times do |i|
      current_day = Date.today + i
      days << {
        :date => current_day,
        :name => Date::DAYNAMES[current_day.wday],
        :milestones => []
      }
    end
    return days
  end
end

