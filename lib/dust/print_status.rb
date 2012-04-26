require 'colorize'

module Dust
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
    print_msg "#{string} #{'[ ok ]'.green}\n", opts
    true
  end

  def self.print_failed string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{'[ failed ]'.red}\n", opts
    false
  end

  def self.print_warning string='', options={:quiet => false, :indent => 1}
    opts = options.clone
    opts[:indent] = 0 if string.empty?
    print_msg "#{string} #{'[ warning ]'.yellow}\n", opts
  end

  def self.print_hostname hostname, options={:quiet => false, :indent => 0}
    print_msg "\n[ #{hostname.blue} ]\n\n", options
  end

  def self.print_recipe recipe, options={:quiet => false, :indent => 0}
    print_msg "|#{recipe}|\n".green, options
  end

  # prints stdout in grey and stderr in red (if existend)
  def self.print_ret ret, options={:quiet => false, :indent => -1}
    opts = options.clone

    opts[:indent] += 1
    print_msg "#{ret[:stdout].chomp.green}\n", opts unless ret[:stdout].empty?
    print_msg "#{ret[:stderr].chomp.red}\n", opts unless ret[:stderr].empty?
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
