# created by Titas Norkūnas
# database-settings control utility for rails projects
# 1. tag database and settings.
# 2. checkout tagged db / settings
# 3. checkout master / tags anytime and do not lose tagged db / settings
# 4. untag when no longer needed
# no conflicting db / settings states between master and prod branch!


namespace :dbtag do
  desc "Create databases (dev & test) and settings backups"
  task :tag do
    unless ENV["tag"] || ENV["t"]
      puts "Please supply t=tagname or tag=tagname parameter for this rake task"
      exit 1
    else
      tag = ENV["tag"] || ENV["t"]
      unless can_tag?(tag) # check if tag is valid
        puts "Sorry, can not tag with #{tag}. Either tag is reserved or you are not on master. See rake dbtag:br"
        exit 1
      end
    end

    dbconfig = YAML.load_file(File.join(RAILS_CONFIG, "database.yml"))

    DEFAULT_ENVS.each do |env|
      if dbconfig[env]
        tag_db(env, dbconfig[env], tag)
      else
        puts "WARNING: #{env} DB not defined in database.yml"
      end
    end

    tag_files(tag)
    add_tag(tag)
  end

  desc "Checkout tagged databases (dev & test) and settings files"
  task :co do
    tag = ENV["tag"] || ENV["t"] || "master"
    puts "Checking out master. Please supply t=tagname or tag=tagname for other tags" if tag == "master"
    unless tag_exists?(tag)
      puts "Tag does not exist!"
      exit 1
    end
    co_files(tag)
    swich_current_tag_to(tag)
  end

  desc "List all tags with current"
  task :br do
    list
  end

  desc "Delete databases (dev & test) and settings backups"
  task :untag do
    unless tag = ENV["tag"] || ENV["t"]
      puts "Please supply t=tagname or tag=tagname parameter for this rake task"
      exit 1
    end
    unless can_untag?(tag)
      puts "Can not untag (unsupported untag if currently on that tag or untagging master)"
      exit 1
    end

    dbconfig = YAML.load_file(File.join(SETTINGS_DIR, "database.yml_#{tag}"))

    DEFAULT_ENVS.each do |env|
      if dbconfig[env]
        untag_db(env, dbconfig[env])
      else
        puts "WARNING: #{env} DB not defined in database.yml"
      end
    end

    untag_files(tag)
    remove_tag(tag)
  end

  private

  # CONSTANTS

  DEFAULT_ENVS       = ["development", "test"]
  TAG_FILE           = "tags.yml"
  SETTINGS_DIR       = "#{Rails.root}/tmp/settings_tags"
  RAILS_CONFIG       = "#{Rails.root}/config/"
  RESERVED_TAGS      = ["master"]
  SUPPORTED_ADAPTERS = ["mysql"] # TODO support more databases

  # TAG QUESTIONS

  # TODO make validation filesystem aware
  # check if tag is valid
  # only possible to tag when in *master* currently
  def can_tag?(tag)
    !RESERVED_TAGS.include?(tag) && current_tag == "master"
  end

  # if not there already
  def can_swich_to?(tag)
    current_tag != tag
  end

  # can not untag if currently on that tag. Aslo can not untag master
  def can_untag?(tag)
    current_tag != tag and tag != "master"
  end

  # tag exists in settings file?
  def tag_exists?(tag)
    tags_config[:tags].include?(tag)
  end


  # TAG SETTINGS HASH

  def add_tag(tag, swich = false)
    tags_config[:tags] << tag
    tags_config[:current] = tag if swich
    save_config(tags_config)
  end

  def remove_tag(tag)
    tags_config[:tags] = tags_config[:tags] - [tag]
    save_config(tags_config)
  end

  def swich_current_tag_to(tag)
    tags_config[:current] = tag
    save_config(tags_config)
  end

  def current_tag
    tags_config[:current]
  end

  # list all tags from TAG_FILE. Mark current with *
  def list
    tags_config[:tags].each do |tag|
      current = tags_config[:current] == tag ? "* " : ""
      puts "#{current}#{tag}"
    end
  end

  # cache hash from TAG_FILE
  def tags_config
    @config ||= open_tags_config
  end

  # save tags hash to file
  def save_config(config)
    save_yaml(File.join(SETTINGS_DIR, TAG_FILE), config)
  end

  # FILESYSTEM

  # create tags of settings files in SETTINGS_DIR
  # RAILS_CONFIG/*.example files are considered example settings files
  # *_tag file is created for every settings file in SETTINGS_DIR
  def tag_files(tag)
    Dir.entries(RAILS_CONFIG).reject do |f|
      !(f.end_with?(".example") || f == "database.yml") # take all example files + database.yml
    end.map{|f| f.gsub(/\.example$/, "")}.uniq.each do |setting| # make sure only one database.yml
      if File.exists?(File.join(RAILS_CONFIG, setting))
        FileUtils.cp(File.join(RAILS_CONFIG, setting), File.join(SETTINGS_DIR, "#{setting}_#{tag}"))
      end

      # update database.yml_tag to use tagged DB's
      if setting == "database.yml"
        file_path = File.join(SETTINGS_DIR, "#{setting}_#{tag}")
        DEFAULT_ENVS.each do |env|
          update_db_settings(file_path, env, tag)
        end
      end
    end
  end

  # delete files that end with tag
  def untag_files(tag)
    Dir.entries(SETTINGS_DIR).reject do |f|
      !(f.end_with?("_#{tag}"))
    end.each do |f|
      FileUtils.rm(File.join(SETTINGS_DIR, f))
    end
  end

  # checkout settings files
  def co_files(tag)
    # save current master files if on master
    if current_tag == "master"
      untag_files("master")
      tag_files("master")
    end
    Dir.entries(SETTINGS_DIR).reject do |f|
      !(f.end_with?("_#{tag}")) # take only with _tag
    end.each do |f|
      setting = f.gsub(/_#{tag}$/, "")
      FileUtils.cp(File.join(SETTINGS_DIR, "#{setting}_#{tag}"), File.join(RAILS_CONFIG, setting))
    end
  end

  # set database setting to database_tag
  # my_app_development => my_app_development_tag
  # my_app_test        => my_app_test_tag
  def update_db_settings(file_path, env, tag)
    config = YAML.load_file(file_path)
    if config[env]
      unless tag == "master"
        config[env]["database"] = "#{config[env]["database"]}_#{tag}"
      end
      save_yaml(file_path, config)
    else
      puts "WARNING: #{env} DB not defined in database.yml"
    end
  end

  # save a yaml config to path
  def save_yaml(path, config)
    File.open(path, "w") do |f|
      f.write(YAML.dump(config))
    end
  end

  # open or create TAG_FILE
  def open_tags_config
    tag_file_path = File.join(SETTINGS_DIR, TAG_FILE)
    Dir.mkdir(SETTINGS_DIR) unless File.exists?(SETTINGS_DIR)
    FileUtils.touch(tag_file_path)
    YAML.load_file(tag_file_path) || {:tags => ["master"], :current => "master"}
  end

  # DATABASES

  # tag a database from selected env
  def tag_db(env, config, tag)
    if SUPPORTED_ADAPTERS.include?(config["adapter"])
      send("tag_#{config['adapter']}", env, config, tag)
    else
      puts "WARNING: Adapter #{config["adapter"]} is not supported. Only #{SUPPORTED_ADAPTERS.join(', ')} supported at this time"
    end
  end

  # untag a database from selected env
  def untag_db(env, config)
    if SUPPORTED_ADAPTERS.include?(config["adapter"])
      send("untag_#{config['adapter']}", env, config)
    else
      puts "WARNING: Adapter #{config["adapter"]} is not supported. Only #{SUPPORTED_ADAPTERS.join(', ')} supported at this time"
    end
  end

  # TODO support host (not localhost)
  # create a mysql backup named title_tag
  def tag_mysql(env, config, tag)
    u = config["username"]
    u = "-u#{u}" if u.present?
    p = config["password"]
    p = "-p#{p}" if p.present?
    title = config["database"]
    title_with_tag = "#{title}_#{tag}"
    res = system "mysqladmin create #{title_with_tag} #{u} #{p} && mysqldump #{u} #{p} #{title} | mysql #{u} #{p} #{title_with_tag}"
    puts "WARNING: problems when creating mysql database for #{env}" unless res
    res
  end

  # TODO support host (not localhost)
  # drop a mysql backup
  def untag_mysql(env, config)
    u = config["username"]
    u = "-u#{u}" if u.present?
    p = config["password"]
    p = "-p#{p}" if p.present?
    title = config["database"]
    res = system "mysqladmin drop #{title} #{u} #{p}"
    puts "WARNING: problems when dropping mysql database for #{env}" unless res
    res
  end
end

