class MainController < ApplicationController
  before_filter :set_campuses, :only => [ :index, :your_campuses, :your_applications ]
  
  skip_before_filter :verify_user, :only => [ :questionnaire ]
  skip_before_filter :verify_event_group_chosen, :only => [ :questionnaire ]
  skip_before_filter :set_event_group, :only => [ :questionnaire ]

  skip_before_filter :set_user, :only => [ :questionnaire ]
  skip_before_filter :get_user, :only => [ :questionnaire ]
  skip_before_filter :restrict_students, :only => [ :questionnaire, :emails ]
  skip_before_filter :ensure_year_set, :only => [ :questionnaire ]
  skip_before_filter :set_campuses, :only => [ :questionnaire ]
  
  CampusStats = Struct.new(:students_cnt, :student_applns, :accepted_cnt, :applied_cnt, :students_no_appln)
  StudentAppln = Struct.new(:student, :appln)
  
  def emails
    if RAILS_ENV =~ /test/ || RAILS_ENV == 'development'
      @emails = ActionMailer::Base.deliveries
    end
  end

  def index
    logger.info 'starting main_controller index'
    # at this point we know the user is not a student
    # 
    # project directors would like to go to my projects
    if @user.is_projects_coordinator?
      flash.keep(:notice)
      redirect_to :action => :your_projects
    else
      # students should go to your projects, that's all they can see -- they might
      #  be interns then they can see support coaches only
      if @user.is_student?
        redirect_to :action => :your_projects
      else
        redirect_to :action => :your_campuses
      end
    end
  end
  
  def edit_form
    @form = Form.find(params[:id])
    # try to reconnect the form by being smart about the name if necssary
    if @form.questionnaire.nil?
      @form.questionnaire_id = Questionnaire.find_by_title("#{@form.year} #{@form.name}").id
      @form.save!
    end
    redirect_to :controller => "questionnaires", :action => "edit", :id => @form.questionnaire_id
  end
  
  def your_campuses
    @current_projects_form = @eg.forms.find_by_hidden(false)
    
    generate_campus_stats(@campuses)
    
    @page_title = "Your Campuses"
  end
  
  def your_projects
    if (@user.is_projects_coordinator?)
      @allowable_projects = @eg.projects.find :all
    else
      @allowable_projects = @user.viewer.current_projects_with_any_role @eg
    end
    
    @allowable_projects_array = []
    @allowable_projects.each { |p| @allowable_projects_array << [p.title, p.id]}
    
    @first_allowable_project = @allowable_projects.first unless @allowable_projects.empty?
    
    @allowable_projects_array << ["All", "all"]
    
    params[:project_id] ||= if @first_allowable_project then @first_allowable_project.id.to_s 
                             else '' end
    if params[:project_id] == 'all'
      @show_projects = @allowable_projects
    else
      requested_project_ids = params[:project_id].split(',') # comma-separated list of projects ids
      @show_projects = @allowable_projects.select{ |p| requested_project_ids.include?(p.id.to_s) }
    # now that we know what projects will be shown with @show_projects, we can do the big query
    #@show_projects = @eg.projects.find @show_projects.collect{ |p| p.id },
    #  :include => [ 
    #    { :acceptances => [
    #        { :viewer => [ 
    #            :vieweraccessgroups, 
    #            { :persons => :campuses } 
    #          ]
    #        },
    #        :projects,
    #         
    #      ]
    #    }
    #  ] end
    end
    @page_title = "Your Projects"
    if request.xml_http_request?
      render :file => 'main/render_your_project.rjs', :use_full_path => true
    else
      render :layout => !request.xml_http_request?
    end
  end
  
  def your_applications
    @page_title = "App Processing"
    if (@user.is_projects_coordinator?)
      processor_for_project_ids = @eg.projects.collect{ |p| p.id }
    else
      # find which projects @user is a processor for
      processor_for_project_ids = Processor.find_all_by_viewer_id(@user.id).collect { 
        |entry| if entry.project.event_group_id == @eg.id then entry.project_id else nil end }.compact
    end
    
    @can_evaluate = true
    @processor_list = Applying.find_all_by_project_id(processor_for_project_ids, :include => :appln)
    @processor_list.delete_if { |pl| pl.appln.status != 'completed' }
    @processor_list.sort{ |a,b| 
      if a.appln.submitted_at.nil? && b.appln.submitted_at
        1
      elsif b.appln.submitted_at.nil? && a.appln.submitted_at
        -1
      elsif a.appln.submitted_at.nil? && b.appln.submitted_at.nil?
        0
      else
        b.appln.submitted_at <=> a.appln.submitted_at
      end
    }
  end
  
  def questionnaire
    @controller = params[:c] || params[:controller]
    headers['Content-Type'] = "text/javascript"
    render :layout => false
  end
  
  def find_people
    name = params[:viewer][:name]
    name.strip!
    fname = name.sub(/ +.+/i, '')
    lname = name.sub(/.+ +/i, '') if name.include? " "
    if !lname.nil?
      @people = Person.find(:all, 
                            :conditions => ["person_fname like ? AND person_lname like ?", "%#{fname}%", "%#{lname}%"],
                            :order => "person_fname, person_lname")
    else
      @people = Person.find(:all, 
                            :conditions => ["person_fname like ? OR person_lname like ?", "%#{fname}%", "%#{fname}%"],
                            :order => "person_fname, person_lname")
    end
    @viewers = @people.collect {|p| p.viewers}.flatten.compact
  end
  
  def get_viewer_specifics
    @viewer = Viewer.find(params[:id], :include => :persons)

    profiles = Profile.find_all_by_viewer_id(@viewer.id)
    @profiles_by_eg = EventGroup.find(:all).collect { |eg|
      [ eg, profiles.find_all { |p| 
        if p.project 
	  p.project.event_group_id == eg.id 
	elsif p.appln && p.appln.form
	  p.appln.form.event_group_id == eg.id
	else
	  false
	end
      } ]
    }

    render :partial => "viewer_specifics"
  end

  def get_viewer_specifics_old
    @viewer = Viewer.find(params[:id], :include => :persons)
    @acceptances_list = Acceptance.find_all_by_viewer_id(@viewer.id, :include => :appln)
    @withdrawns_list = Withdrawn.find_all_by_viewer_id(@viewer.id, :include => :appln)
    @processor_lists_list = Applying.find_all_by_viewer_id(@viewer.id, :include => :appln)
    #@processor_lists_list.delete_if { |pl| pl.appln.status != 'completed' }
    @processor_lists_list.sort{ |a,b| 
      b.appln.submitted_at <=> a.appln.submitted_at
    }
    #@staffs = nil
    @staffs_list = Profile.find(:all, 
    :conditions => ["profiles.viewer_id = ? and profiles.type = ?", @viewer.id, "StaffProfile"])
    @applns = Appln.find_all_by_viewer_id @viewer.id, :include => :profiles
    #@applns.reject!{ |a| ![ 'withdrawn', 'declined', 'started', 'unsubmitted' ].include?(a.status) }
    @full_view = @user.fullview?
    @projects = true

    # sort the different findings into event groups
    #        if !@accepted.empty? || !@processor_list.empty? || !@staff.empty? || !@withdrawn.empty?
    #
    @acceptances = {}
    @acceptances_list.each do |a| eg = a.form.event_group; 
       @acceptances[eg] ||= []; @acceptances[a.form.event_group] << eg;
    end
    @processor_lists = {}
    @processor_lists_list.each do |a| eg = a.form.event_group; 
       @processor_lists[eg] ||= []; @processor_lists[a.form.event_group] << eg;
    end
    @acceptances = {}
    @acceptances_list.each do |a| eg = @acceptances[a.form.event_group_id]; 
       @acceptances[eg] ||= []; @acceptances[a.form.event_group] << eg;
    end
render :partial => "viewer_specifics"
  end
  
  def search_people_by_name
    @page_title = "Search"
  end
  
  protected
  
  def generate_campus_stats(campuses)
    @campus_stats = { }
    for campus in campuses
      @campus_stats[campus] = CampusStats.new
      
      @campus_stats[campus].students_cnt = 0
      @campus_stats[campus].student_applns = [ ]
      @campus_stats[campus].students_no_appln = [ ]
      @campus_stats[campus].accepted_cnt = 0
      @campus_stats[campus].applied_cnt = 0
      
      next if @current_projects_form.nil?

      for student in campus.students
        @campus_stats[campus].students_cnt += 1
        students_current_applns = student.viewers.collect{ |v| 
	  v.applns.select { |a| a.form_id == @current_projects_form.id }
	}.compact.flatten
        
        for students_current_appln in students_current_applns
          @campus_stats[campus].student_applns << StudentAppln.new(student, students_current_appln)
          
          if students_current_appln.profile.class == Acceptance
            @campus_stats[campus].accepted_cnt += 1
            @campus_stats[campus].applied_cnt += 1
	  elsif students_current_appln.profile.class == Applying
            @campus_stats[campus].applied_cnt += 1
          end
        end
      end
    end
  end
  
  def set_campuses
    @campuses = @user ? users_campuses(@user) : []
  end
  
  def users_campuses(user)
    campuses = nil
    if (user.is_projects_coordinator? || 
    user.is_assigned_regional_or_national?)
      campuses = Campus.find(:all)
    else
      campuses = @user.viewer.person.campuses
    end
    campuses
  end
 
  private

end