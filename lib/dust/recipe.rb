class Recipe < Thor

  desc 'prepare', 'prepare recipe (do not use manually)'
  def prepare node, recipe, context, config, options

    # prepare class variables
    @template_path = "./templates/#{recipe}"
    @node = node
    @config = config
    @options = options

    # run task
    send context
  end
end
