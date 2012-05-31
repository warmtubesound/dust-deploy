class Cron < Recipe

  desc 'cron:deploy', 'maintains cronjobs'
  def deploy
    # check config
    # install cron
    # enable name: remove to remove a job

    unless @node.dir_exists? '/etc/cron.d'
      return @node.messages.add('your system does not support /etc/cron.d').failed
    end

    @config.each do |name, job|
      # remove job if requested
      if job == 'remove'
        remove(name)
        next
      end

      @node.messages.add("processing cronjob '#{name}'\n")

      # apply default settings, unless set
      job = default_job.merge job

      parse_cronjob(job)
      next unless check_cronjob(job)
      cronjob = generate_cronjob(job)

      # deploy rule file
      msg = @node.messages.add('deploying', :indent => 2)
      msg.parse_result(@node.write("/etc/cron.d/#{name}", cronjob, :quiet => true))
    end
  end


  private

  # removes all files in /etc/cron.d/
  def remove(name)
    msg = @node.messages.add("removing cronjob #{name}")
    msg.parse_result(@node.rm("/etc/cron.d/#{name}", :quiet => true))
  end

  # default settings for a cronjob
  def default_job
    { 'minute' => '*', 'hour' => '*', 'monthday' => '*',
      'month' => '*', 'weekday' => '*', 'user' => 'root' }
  end

  def generate_cronjob(job)
    "#{job['minute']} #{job['hour']} #{job['monthday']} " +
    "#{job['month']} #{job['weekday']} #{job['user']} " +
    "#{job['command']}\n"
  end

  # translate month and day names to numbers
  def parse_cronjob(job)

    # valid months and days
    months = { 'january' => 1,    'jan' => 1,
               'february' => 2,   'feb' => 2,
               'march' => 3,      'mar' => 3,
               'april' => 4,      'apr' => 4,
               'may' => 5,
               'june' => 6,       'jun' => 6,
               'july' => 7,       'jul' => 7,
               'august' => 8,     'aug' => 8,
               'september' => 9,  'sep' => 9,
               'october' => 10,   'oct' => 10,
               'november' => 11,  'nov' => 11,
               'december' => 12,  'dec' => 12 }

    days = { 'sunday' => 0,       'sun' => 0,
             'monday' => 1,       'mon' => 1,
             'tuesday' => 2,      'tue' => 2,
             'wednesday' => 3,    'wed' => 3,
             'thursday' => 4,     'thu' => 4,
             'friday' => 5,       'fri' => 5,
             'saturday' => 6,     'sat' => 6 }

    # only process, if month is a string
    if job['month'].is_a? String and not job['month'] == '*'
      m = []

      # multiple month are allowed, splitting using ','
      job['month'].split(',').each do |i|

        # if month is an int, add it to list and continue
        if i.is_int?
          d << i.to_i
          next
        end

        # find month number in hash, add it to list
        if  months[i.downcase]
          m << months[i.downcase]

        # if month is not found, add -1 (will throw error on check_cronjob later)
        else
          m << -1
        end

      end

      # join the numbers pack together
      job['month'] = m.join(',')
    end

    # do the same with weekdays
    if job['weekday'].is_a? String and not job['weekday'] == '*'
      d = []
      job['weekday'].split(',').each do |i|
        if i.is_int?
          d << i.to_i
          next
        end

        if  days[i.downcase]
          d << days[i.downcase]
        else
          d << -1
        end
      end
      job['weekday'] = d.join(',')
    end

  end

  # check if cronjob is valid
  def check_cronjob(job)
    msg = @node.messages.add('validating', :indent => 2)

    return msg.failed(': no command given') unless job['command'].is_a? String
    return msg.failed(': invalid user') unless job['user'].is_a? String
    return msg.failed(': minute field invalid') unless check_period(job['minute'], 0, 59)
    return msg.failed(': hour field invalid') unless check_period(job['hour'], 0, 23)
    return msg.failed(': monthday field invalid') unless check_period(job['monthday'], 1, 31)
    return msg.failed(': month field invalid') unless check_period(job['month'], 1, 12)
    return msg.failed(': weekday field invalid') unless check_period(job['weekday'], 0, 6)

    msg.ok
  end

  # check if a cronjob time period is valid
  def check_period(period, from, to)
    # if period is an int, directly check if it's between from and to
    return period.to_i.between?(from, to) if period.is_a? Fixnum

    # cron supports multiple periods
    # and e.g */5 for e.g. every 5 minutes/hours
    period.split(/[\/,]/).each do |p|
      next if p.is_int? and p.to_i.between?(from, to)
      next if p == '*'

      # if none of the criteria matches, this period is invalid.
      return false
    end

    true
  end
end
