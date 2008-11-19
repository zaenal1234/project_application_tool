class EventGroup < Node
  belongs_to :ministry
  belongs_to :location

  has_many :custom_reports
  has_many :projects
  has_many :forms
  has_many :travel_segments
  has_many :cost_items
  has_many :feedbacks
  has_many :forms
  has_many :reason_for_withdrawals
  has_many :reference_emails
  has_many :tags

  acts_as_tree

  has_attachment :content_type => :image, 
                 :storage => :file_system

  attr :filter_hidden, true

  def has_logo?() !filename.nil? end

  def classes(section = nil)
    classes = []

    if section == :a
      classes << 'event_group_hidden' if hidden
    elsif section == :li
      classes << 'event_group_has_logo' if filename
      classes << 'event_group_top_level' if parent.nil?
    end

    classes.join(' ')
  end

  def children_with_hidden_check
    if filter_hidden
      c = children_without_hidden_check.reject{ |c| c.hidden? }
      c.each{ |c| c.filter_hidden = true }
    else
      children_without_hidden_check
    end
  end
  alias_method_chain :children, :hidden_check

  # returns the ministry followed by the entire path of parents in the event group tree
  def to_s_with_ministry_and_eg_path
    "#{[ministry_inherited_name, eg_path].compact.join(' - ')}"
  end
  
  def to_s_with_eg_path
    "#{eg_path}"
  end

  def ministry_inherited_name
    m = ministry_inherited
    m ? "#{m.name} " : ''
  end

  def eg_path
    visited = { self => true }

    eg_path = ''
    node = self
    while !node.nil?
      eg_path = eg_path.empty? ? node.title : (node.title + ' - ' + eg_path)
      node = node.parent

      if visited[node]
        node = nil
      else
        visited[node] = true
      end
    end

    eg_path
  end

  def to_s
    title
  end

  def ministry_inherited
    node = self
    while node.ministry.nil? && !node.parent_id.nil?
      node = node.parent
    end

    node.ministry
  end

  def ensure_emails_exist
    ReferenceEmailsController.types.each_pair do |type_key, type_desc|
      existing = self.reference_emails.find_by_email_type(type_key)
      if (existing == nil)
        # use the default one if possible
        path = File::join(RAILS_ROOT, "app/views/reference_emails/#{type_key}.default.rhtml")
        if File.exists?(path)
          text = File.read(path)
        else
          text = type_desc
        end

        ReferenceEmail.create :email_type => type_key,
          :event_group_id => self.id,
          :text => text
      end
    end
  end

end
