class MembersController < ApplicationController

  include OauthSystem

  before_filter :oauth_login_required, :except => [ :callback, :signout, :index ]

  before_filter :init_member, :except => [ :callback, :signout, :index ]

  before_filter :access_check, :except => [ :callback, :signout, :index ]


  # GET /members
  # GET /members.xml
  def index
  end

  def new
    # this is a do-nothing action, provided simply to invoke authentication
    # on successful authentication, user will be redirected to 'show'
    # on failure, user will be redirected to 'index'
  end
  
  # GET /members/1
  # GET /members/1.xml
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @member }
    end
  end

  def guess_friend
    game_id = session[:game_id].to_i
    guess_id = params[:guess_id].to_i 
    @user_image = session[:game_image]
    @user_name = session[:game_name]
    if(game_id == guess_id)
      @gameStatus = 'winner'
      @message = 'You have chosen wisely'
    else
      @gameStatus = 'loser'
      @message = 'You have chosen... unwisely'
    end
    render :partial => 'members/game_over', :layout => false
  end

  def show_graph
    if (request.xhr?)
      difficulty = params[:difficulty]
      count = case difficulty
        when "easy" then 4
        when "medium" then 9
        when "hard" then 17
        else 4
      end
      @gameClass = case difficulty
        when "hard" then "hard"
        else "easy"
      end
      friends = self.friends()
      #create a list of potential friends with enough
      #status updates to use in the game
      @candidates = []
      friends.each do |friend|
        if (false == friend['statuses_count'].nil? and friend['statuses_count'] > 50)
          @candidates << friend
        end
      end
      #if there are not enough friends found throw an error
      if (@candidates.empty? or @candidates.length <= count)
        raise 'Not enough friends'
      end
      #take a random selection of candidates as the final list
      #of friends to select from, then pick the "guess" person
      @candidates = @candidates.sort{ rand() - 0.5 }[0..count]
      guess_id = rand(count)
      #get a random status update from the selected person
      unless @candidates[guess_id]['id']
        raise 'Error with user status updates. please try again.'
      end
      statuses = self.statuses(@candidates[guess_id]['id'], 50)
      unless statuses
        raise 'Error getting statuses'
      end
      random_status = rand(statuses.length)
      max_tries = 0
      while !statuses[random_status]
        random_status = rand(statuses.length)
        max_tries += 1
      end
      unless statuses[random_status]
        raise 'Error getting status message'
      end
      @quote = stripEntities(statuses[random_status])
      session[:game_id] = @candidates[guess_id]['id']
      session[:game_quote_index] = [random_status]
      session[:game_image] = @candidates[guess_id]['profile_image_url']
      session[:game_name] = @candidates[guess_id]['screen_name']
      session[:game_countdown] = 5
      render :partial => 'members/game', :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  rescue => err
    render :text => err, :status => 500
  end

  def get_quote
    if (request.xhr?)
      if(session[:game_countdown] <= 0)
        raise 'No more hints allowed'
      end
      
      friend_id = session[:game_id]
      quote_list = session[:game_quote_index]
      statuses = self.statuses(friend_id, 50)
      unless statuses
        raise 'Error getting statuses'
      end
      pick_list = (0..statuses.length).to_a - quote_list
      new_index = pick_list[rand(pick_list.length)]
      
      if(statuses[new_index].nil?)
        raise 'Error with status. please try again'
      end
      
      @quote = stripEntities(statuses[new_index])
      session[:game_quote_index] = quote_list << new_index
      session[:game_countdown] -= 1
      @countdown = session[:game_countdown]
      render :partial => 'members/quote', :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  rescue => err
    render :text => err, :status => 500
  end

  def update_status
    if self.update_status!(params[:status_message])
      flash[:notice] = 'status update sent'
    else
      flash[:error] = 'status update problem'
    end
    redirect_to member_path(@member)
  end

  def partialfriends
    if (request.xhr?)
      @friends = self.friends()
      render :partial => 'members/friend', :collection => @friends, :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  end

  def partialfollowers
    if (request.xhr?)
      @followers = self.followers()
      render :partial => 'members/friend', :collection => @followers, :as => :friend, :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  end

  def partialmentions
    if (request.xhr?)
      @messages = self.mentions()
      render :partial => 'members/status', :collection => @messages, :as => :status, :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  end

  def partialdms
    if (request.xhr?)
      @messages = self.direct_messages()
      render :partial => 'members/direct_message', :collection => @messages, :as => :direct_message, :layout => false
    else
      flash[:error] = 'method only supporting XmlHttpRequest'
      member_path(@member)
    end
  end


  def stripEntities(status)
    puts 'a'
    if status['entities'].nil?
      status['text']
    else
      puts 'b'
      text = status['text']
      unless status['entities']['urls'].nil?
        status['entities']['urls'].each do |url|
          text[url['indices'][0]..url['indices'][1]] = '<span class="insert">deleted</span>'
        end
      end
      puts'c'
      unless status['entities']['hashtags'].nil?
        status['entities']['hashtags'].each do |url|
          text[url['indices'][0]..url['indices'][1]] = '<span class="insert">deleted</span>'
        end
      end
      puts 'd'
      unless status['entities']['user_mentions'].nil?
        status['entities']['user_mentions'].each do |url|
          text[url['indices'][0]..url['indices'][1]] = '<span class="insert">deleted</span>'
        end
      end
      puts "text #{text}"
      text
    end
  end
  
protected

  # controller helpers
  
  def init_member
    begin
      screen_name = params[:id] unless params[:id].nil?
      screen_name = params[:member_id] unless params[:member_id].nil?
      @member = Member.find_by_screen_name(screen_name)
      raise ActiveRecord::RecordNotFound unless @member
    rescue
      flash[:error] = 'Sorry, that is not a valid user.'
      redirect_to root_path
      return false
    end
  end
  
  
  def access_check
    return if current_user.id == @member.id
    flash[:error] = 'Sorry, permissions prevent you from viewing other user details.'
    redirect_to member_path(current_user) 
    return false    
  end 

  

end