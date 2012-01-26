module Dust
  # colors for terminal
  def self.red thick=1;      "\033[#{thick};31m"; end
  def self.green thick=1;    "\033[#{thick};32m"; end
  def self.yellow thick=1;   "\033[#{thick};33m"; end
  def self.blue thick=1;     "\033[#{thick};34m"; end
  def self.pink thick=1;     "\033[#{thick};35m"; end
  def self.turquois thick=1; "\033[#{thick};36m"; end
  def self.grey thick=1;     "\033[#{thick};37m"; end
  def self.black thick=1;    "\033[#{thick};38m"; end
  def self.none;             "\033[0m"; end

  $stdout.sync = true # autoflush

  def self.print_result ret, options={:quiet => false, :indent => 1}
    if ret == 0 or ret == true
      print_ok '', options
      return true
    else
      print_failed '', options
      return false
    end
  end

  def self.print_ok string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{blue}[ ok ]#{none}\n", opts
    true
  end

  def self.print_failed string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{red}[ failed ]#{none}\n", opts
    false
  end

  def self.print_warning string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{yellow}[ warning ]#{none}\n", opts
  end

  def self.print_hostname hostname, options={:quiet => false, :indent => 0}
    print_msg "\n[ #{blue}#{hostname}#{none} ]\n\n", options
  end

  def self.print_recipe recipe, options={:quiet => false, :indent => 1}
    print_msg "#{green}|#{recipe}|#{none}\n", options
  end

  # indent according to options[:indent]
  # indent 0
  #  - indent 1
  #    - indent 2
  def self.print_msg string, options={:quiet => false, :indent => 1}
    # just return if in quiet mode
    return if options[:quiet]

    options[:indent] ||= 1

    if options[:indent] == 0
      print string
    else
      print ' ' + '  ' * (options[:indent] - 1) + '- ' + string
    end
  end

end
