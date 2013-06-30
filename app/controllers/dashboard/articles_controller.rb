class Dashboard::ArticlesController < Dashboard::BaseController
  before_filter :find_article, :only => [:show, :status, :edit, :update]
  before_filter :find_articles, :only => [:batch_category, :batch_trash, :batch_publish, :batch_draft, :batch_restore, :batch_destroy]
  before_filter :check_lock_status, :only => [:update]

  def index
    @articles = @space.articles.desc(:updated_at).page(params[:page]).per(15).status(params[:status]).includes(:category)
  end

  def uncategorized
    @articles = @space.articles.desc(:updated_at).page(params[:page]).per(15).status(params[:status]).where(:category_id => nil)

    render :index
  end

  def trashed
    @articles = @space.articles.desc(:updated_at).page(params[:page]).status('trash').includes(:category)
  end

  def categorized
    @category = @space.categories.find_by :token => param_to_token(params[:category_id])
    @articles = @space.articles.desc(:updated_at).page(params[:page]).per(15).status(params[:status]).where(:category_id => @category.id)

    render :index
  end

  def show
    basename = if @article.urlname.present?
                 "#{@article.token}-#{@article.urlname}"
               else
                 @article.token
               end

    respond_to do |format|
      format.md do
        send_file(ArticleDownload.new(@article).build_md,
                  :filename => "#{basename}.md")
      end

      format.docx do
        send_file(ArticleDownload.new(@article).build_docx,
                  :filename => "#{basename}.docx")
      end

      format.odt do
        send_file(ArticleDownload.new(@article).build_odt,
                  :filename => "#{basename}.odt")
      end
    end
  end

  def new
    @article = @space.articles.new
    if params[:category_id]
      @article.category = @space.categories.where(:token => param_to_token(params[:category_id])).first
    end
    append_title @article.title
    render :edit, :layout => false
  end

  def create
    @article = @space.articles.new article_params.merge(:last_edit_user => current_user)
    if @article.save
      @article.create_version

      render :article
    else
      render :json => { :message => @article.errors.full_messages.join }, :status => 400
    end
  end

  def status
  end

  def edit
    append_title @article.title

    if params[:note_id]
      @note = @article.notes.where(:token => params[:note_id]).first
    end

    render :layout => false
  end

  def update
    if @article.last_edit_user && @article.last_edit_user != current_user
      @article.create_version :user => @article.last_edit_user
    end

    if article_params[:save_count].to_i > @article.save_count
      if @article.update_attributes article_params.merge(:last_edit_user => current_user)

        if @article.save_count - @article.last_version_save_count >= 100
          @article.create_version :user => current_user
        end

        render :article
      else
        respond_to do |format|
          format.json { render :json => { :message => @article.errors.full_messages.join }, :status => 400 }
        end
      end
    else
      render :json => { :message => I18n.t('save_count_expired'), :code => 'save_count_expired' }, :status => 400
    end
  end

  def empty_trash
    @space.articles.trash.destroy_all
  end

  def batch_category
    @category = @space.categories.find_by(:token => param_to_token(params[:category_id]))
    @articles.untrash.update_all :category_id => @category.id

    render :batch_update
  end

  def batch_trash
    @articles.untrash.update_all :status => 'trash'

    render :batch_update
  end

  def batch_publish
    @articles.untrash.update_all :status => 'publish'

    render :batch_update
  end

  def batch_draft
    @articles.untrash.update_all :status => 'draft'

    render :batch_update
  end

  def batch_restore
    @articles.trash.where(:status => 'trash').update_all :status => 'draft'

    render :batch_update
  end

  def batch_destroy
    @articles.trash.destroy_all

    render :batch_update
  end

  private

  def find_article
    @article = @space.articles.find_by(:token => params[:id])
  end

  def find_articles
    @articles = @space.articles.where(:token.in => params[:ids])
  end

  def article_params
    base_params = params.require(:article).permit(:title, :body, :urlname, :status, :save_count)

    if params[:article][:category_id]
      base_params.merge!(:category => @space.categories.where(:token => param_to_token(params[:article][:category_id])).first)
    end

    base_params
  end

  def check_lock_status
    if @article.locked? and !@article.locked_by?(current_user)
      locked_user = User.where(:id => @article.locked_by).first
      render :json => { :message => I18n.t('is_editing', :name => @article.locked_by_user.name ), :code => 'article_locked', :locked_user => { :name => locked_user.try(:name) } }, :status => 400
    else
      @article.lock_by(current_user)
    end
  end
end
