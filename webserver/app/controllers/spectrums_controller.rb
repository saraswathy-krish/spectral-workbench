require 'will_paginate/array'
class SpectrumsController < ApplicationController
  protect_from_forgery :only => [:clone, :extract, :calibrate]
  # http://api.rubyonrails.org/classes/ActionController/RequestForgeryProtection/ClassMethods.html
  # create and update are protected by recaptcha

	  # GET /spectrums
  # GET /spectrums.xml
  def index
    @spectrums = Spectrum.find(:all,:order => "created_at DESC")
    @spectrums = @spectrums.paginate :page => params[:page], :per_page => 24
    @sets = SpectraSet.find(:all,:limit => 4,:order => "created_at DESC")
    @comments = Comment.all :limit => 12, :order => "id DESC"

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @spectrums }
    end
  end

  # GET /spectrums/1
  # GET /spectrums/1.xml
  # GET /spectrums/1.json
  def show
    @spectrum = Spectrum.find(params[:id])
    if @spectrum.data == "" || @spectrum.data.nil?
      @spectrum.extract_data 
      @spectrum.save 
    end
    @comment = Comment.new

    @spectrums = Spectrum.find(:all, :limit => 4, :order => "created_at DESC", :conditions => ["id != ?",@spectrum.id])

    respond_to do |format|
      format.html { render 'spectrums/show' } # show.html.erb
      format.xml  { render :xml => @spectrum }
      format.json  { render :json => @spectrum }
    end
  end

  # non REST
  def embed
    @spectrum = Spectrum.find(params[:id])
    render :layout => false 
  end

  # non REST
  def author
    @spectrums = Spectrum.find_all_by_author(params[:id])
    @spectrums = @spectrums.paginate :page => params[:page], :per_page => 24
    render "spectrums/search"
  end

  # non REST
  def compare
    @spectrum = Spectrum.find(params[:id])
    @spectrums = Spectrum.find(:all, :conditions => ['id != ? AND (title LIKE ? OR notes LIKE ?)',@spectrum.id,"%"+params[:q]+"%", "%"+params[:q]+"%"],:limit => 100,:order => "created_at DESC")
    render :partial => "compare", :layout => false
  end

  # non REST
  def search
    params[:id] = params[:q]
    @spectrums = Spectrum.find(:all, :conditions => ['title LIKE ? OR notes LIKE ?',"%"+params[:id]+"%", "%"+params[:id]+"%"],:limit => 100)
    @spectrums = @spectrums.paginate :page => params[:page], :per_page => 24
  end

  # non REST
  def detail
    @spectrum = Spectrum.find(params[:id])

    respond_to do |format|
      format.html # details.html.erb
    end
  end

  # GET /spectrums/new
  # GET /spectrums/new.xml
  def new
    if logged_in?
    @spectrum = Spectrum.new

    respond_to do |format|
      format.html # new.html.erb 
      format.xml  { render :xml => @spectrum }
    end
    else
      flash[:error] = "You must be logged in to upload a new spectrum."
      redirect_to "/login"
    end
  end

  # GET /spectrums/1/edit
  def edit
    @spectrum = Spectrum.find(params[:id])
    if (params[:login] && params[:client_code]) || (logged_in? && (@spectrum.user_id == current_user.id || current_user.role == "admin"))
    else
      flash[:error] = "You must be logged in and own this spectrum to edit."
      redirect_to "/login"
    end
  end

  # POST /spectrums
  # POST /spectrums.xml
  # ?spectrum[title]=TITLE&spectrum[author]=anonymous&client=VERSION&uniq_id=UNIQID&startWavelength=STARTW&endWavelength=ENDW;
  def create
    if params[:client] || logged_in?
      client = params[:client] || "0"
      uniq_id = params[:uniq_id] || "0"
      client_code = client+"::"+uniq_id
      puts client_code
      user_id = current_user.id if logged_in?
      user_id ||= "0"
      author = current_user.login if logged_in?
      author ||= "anonymous"

      if params[:photo]
        @spectrum = Spectrum.new({:title => params[:spectrum][:title],
				  :author => author,
				  :user_id => user_id,
				  :photo => params[:photo]})
        @spectrum.client_code = client_code if params[:client] || params[:uniq_id]
      else
        @spectrum = Spectrum.new({:title => params[:spectrum][:title],
				  :author => author,
				  :user_id => user_id,
				  :photo => params[:spectrum][:photo]})
      end

      respond_to do |format|
        if (params[:client] || (APP_CONFIG["local"] || verify_recaptcha(:model => @spectrum, :message => "ReCAPTCHA thinks you're not a human!"))) && @spectrum.save!
          if (params[:client]) # java client
	    if params[:photo]
              @spectrum = Spectrum.find @spectrum.id
              @spectrum.extract_data
              @spectrum.scale_data(params[:endWavelength],params[:startWavelength])
              @spectrum.save!
            end
          if logged_in?
            format.html { render :text => @spectrum.id }
          else
            format.html { render :text => @spectrum.id.to_s+"?login=true&client_code="+client+"::"+uniq_id} # <== here, also offer a unique code or pass client_id so that we can persist login
          end
        else
          flash[:notice] = 'Spectrum was successfully created.'
          format.html { 
		redirect_to :action => :show, :id => @spectrum.id
	  }
          format.xml  { render :xml => @spectrum, :status => :created, :location => @spectrum }
        end
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @spectrum.errors, :status => :unprocessable_entity }
      end
    end
    else
      # possibly, we don't have to redirect - we could prompt for login at the moment of save...
      flash[:notice] = "You must first log in to upload spectra."
      redirect_to "/login"
    end
  end

  # PUT /spectrums/1
  # PUT /spectrums/1.xml
  def update
    @spectrum = Spectrum.find(params[:id])
    if logged_in? && (@spectrum.user_id == current_user.id || current_user.role == "admin")
    if @spectrum.author == "anonymous"
      @spectrum.author = current_user.login
      @spectrum.user_id = current_user.id
    end

    respond_to do |format|
      if (@spectrum.update_attributes(params[:spectrum]) && (@spectrum.user_id = User.find_by_login(params[:spectrum][:author]).id) && @spectrum.save)
        flash[:notice] = 'Spectrum was successfully updated.'
        format.html { redirect_to(@spectrum) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @spectrum.errors, :status => :unprocessable_entity }
      end
    end
    else
      flash[:error] = "You must be logged in to edit a spectrum."
      redirect_to "/login"
    end
  end

  # DELETE /spectrums/1
  # DELETE /spectrums/1.xml
  def destroy
    @spectrum = Spectrum.find(params[:id])
    if logged_in? && (current_user.role == "admin" || current_user.id == @spectrum.user_id)
      @spectrum.destroy

    respond_to do |format|
      format.html { redirect_to(spectrums_url) }
      format.xml  { head :ok }
    end
    else
      flash[:error] = "You must be an admin to destroy comments."
      redirect_to "/login"
    end
  end

  def comment
    @spectrum = Spectrum.find(params[:id])
    @spectrums = Spectrum.find(:all, :limit => 4, :order => "created_at DESC", :conditions => ["id != ?",@spectrum.id])
    @jump_to_comment = true
    @comment = Comment.new({
	:spectrum_id => @spectrum.id,
	:body => params[:comment][:body],
	:author => params[:comment][:author],
	:email => params[:comment][:email]})
    @comment.author = current_user.login if logged_in?
    @comment.email = current_user.email if logged_in?
    if (logged_in? || APP_CONFIG["local"] || verify_recaptcha(:model => @comment, :message => "ReCAPTCHA thinks you're not a human!")) && @comment.save
      flash[:notice] = "Comment saved."
      redirect_to "/spectra/"+params[:id]+"#comment_"+@comment.id.to_s
    else
      render :action => "show", :id => params[:id]
    end
  end

  # non REST
  #def calibrate(x1,wavelength1,x2,wavelength2)
  def calibrate
    @spectrum = Spectrum.find(params[:id])
    if logged_in? && @spectrum.user_id == current_user.id
    if request.post?
      @spectrum.calibrate(params[:x1],params[:w1],params[:x2],params[:w2]).save
      @spectrum.save
    end
    redirect_to "/spectra/show/"+@spectrum.id.to_s
    else
      flash[:error] = "You must be logged in and own this spectrum to calibrate."
      redirect_back
    end
  end

  # non REST
  def extract
    @spectrum = Spectrum.find(params[:id])
    if logged_in? && @spectrum.user_id == current_user.id
    if request.post?
      @spectrum.extract_data
      @spectrum.save
    end
    redirect_to "/spectra/show/"+@spectrum.id.to_s
    else
      flash[:error] = "You must be logged in and own this spectrum to re-extract values."
      redirect_back
    end
  end

  # non REST
  def clone
    @spectrum = Spectrum.find(params[:id])
    if logged_in? && @spectrum.user_id == current_user.id
    if request.post?
      @spectrum.clone(params[:clone_id])
      @spectrum.save
    end
    redirect_to "/spectra/show/"+@spectrum.id.to_s
    else
      flash[:error] = "You must be logged in and own this spectrum to clone calibrations."
      redirect_to "/login"
    end
  end

  def all
    @spectrums = Spectrum.find(:all)
    respond_to do |format|
      format.xml  { render :xml => @spectrums }
      format.json  { render :json => @spectrums }
    end
  end

  def assign
    if current_user.role == "admin"
      if params[:claim] == "true"
        # assign each spectrum the current user's id
        @user = User.find_by_login(params[:id])
        @spectrums = Spectrum.find_all_by_author(params[:author])
        @spectrums.each do |spectrum|
          spectrum.user_id = @user.id
          spectrum.author = @user.login
          spectrum.save
        end
        flash[:notice] = "Assigned "+@spectrums.length.to_s+" spectra to "+@user.login
        redirect_to "/"
      else
        @spectrums = Spectrum.find_all_by_author(params[:author])
      end
    else
      flash[:error] = "You must be logged in and be an admin to assign spectra."
      redirect_to "/login"
    end
  end

  def rss
    if params[:author]
      @spectrums = Spectrum.find_all_by_author(params[:author],:order => "created_at DESC",:limit => 12)
    else
      @spectrums = Spectrum.find(:all,:order => "created_at DESC",:limit => 12)
    end
    render :layout => false
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
  end

  def plots_rss
    @spectrums = Spectrum.find(:all,:order => "created_at DESC",:limit => 12, :conditions => ["author != ?","anonymous"])
    render :layout => false
    response.headers["Content-Type"] = "application/xml; charset=utf-8"
  end

end
