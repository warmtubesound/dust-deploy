require 'erb'

class Motd < Recipe
  desc 'motd:deploy', 'creates message of the day'
  def deploy
    return @node.messages.add('no motd or motd template given') unless @config.is_a? String

    file = "#{@template_path}/#{@config}"

    # use the file, or file.erb if present
    # if not, use the given string
    if File.exists?(file)
      @node.messages.add("found static motd file '#{File.basename(file)}'").ok
      message = File.read(file)
    elsif File.exists?(file + '.erb')
      @node.messages.add("found template motd file '#{File.basename(file)}.erb'").ok
      message = ERB.new(File.read(file + '.erb'), nil, '%<>').result(binding)
    else
      @node.messages.add("found motd string in config file").ok
      message = ERB.new(@config, nil, '%<>').result(binding)
    end

    # check if /etc/update-motd.d is present
    if @node.dir_exists?('/etc/update-motd.d', :quiet => true)
      file = '/etc/update-motd.d/50-dust'
      msg = @node.messages.add("update-motd was found, deploying motd to #{file}")

      # create a simple shellscript that echos the motd, and deploy it
      msg.parse_result(@node.write(file, shellscriptify(message), :quiet => true))

      # since we've deployed a shellscript, make it executeable
      @node.chmod('0755', file)

    # not using update-motd, simply modify /etc/motd
    else
      msg = @node.messages.add('deploying message of the day directly to /etc/motd')
      msg.parse_result(@node.write('/etc/motd', message, :quiet => true))
    end
  end
  
  desc 'motd:status', 'shows current message of the day'
  def status
    msg = @node.messages.add('getting /etc/motd')
    ret = @node.exec 'cat /etc/motd'
    msg.parse_result(ret[:exit_code])
    msg.parse_output(ret)
  end


  private

  # creates a shellscript echoing string
  def shellscriptify(string)
    "#!/bin/sh\n\ncat <<EOF\n#{string}\nEOF\n"
  end
end
