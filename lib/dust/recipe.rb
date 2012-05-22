class Recipe < Thor

  desc 'prepare', 'prepare recipe (do not use manually)'
  def prepare node, recipe, context, config, options

    # prepare class variables
    @template_path = "./templates/#{recipe}"
    @node = node
    @options = options

    # if this recipe just was defined as true, yes or 'enabled',
    # continue with empty @config, so defaults get used
    if config.is_a? TrueClass or config == 'enabled'
      @config = {}
    else
      @config = config
    end

    # prepare messaging class for this recipe
    @node.messages.start_recipe(recipe)

    # run task
    send context
  end
end
