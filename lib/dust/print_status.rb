module Dust
  # colors for terminal
  def self.none(t=1);     colorize(0, t); end
  def self.red(t=1);      colorize(1, t); end
  def self.green(t=1);    colorize(2, t); end
  def self.yellow(t=1);   colorize(3, t); end
  def self.blue(t=1);     colorize(4, t); end
  def self.pink(t=1);     colorize(5, t); end
  def self.turquois(t=1); colorize(6, t); end
  def self.grey(t=1);     colorize(7, t); end
  def self.black(t=1);    colorize(8, t); end

  $stdout.sync = true # autoflush

  def self.print_result ret, options={:quiet => false, :indent => 1}
    if ret == 0 or ret.is_a? TrueClass
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
    print_msg "#{string} #{blue}[ ok ]#{none}\n", opts
    true
  end

  def self.print_failed string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{red}[ failed ]#{none}\n", opts
    false
  end

  def self.print_warning string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{yellow}[ warning ]#{none}\n", opts
  end

  def self.print_hostname hostname, options={:quiet => false, :indent => 0}
    print_msg "\n[ #{blue}#{hostname}#{none} ]\n\n", options
  end

  def self.print_recipe recipe, options={:quiet => false, :indent => 0}
    print_msg "#{green}|#{recipe}|#{none}\n", options
  end

  # prints stdout in grey and stderr in red (if existend)
  def self.print_ret ret, options={:quiet => false, :indent => -1}
    opts = options.clone

    opts[:indent] += 1
    print_msg "#{green 0}#{ret[:stdout].chomp}#{none}\n", opts unless ret[:stdout].empty?
    print_msg "#{red 0}#{ret[:stderr].chomp}#{none}\n", opts unless ret[:stderr].empty?
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


  private

  def colorize(no, t = 1)
    return '' unless $stdout.tty?
    return "\033[0m" if no == 0
    "\033[#{t};3#{no}m"
  end
end
