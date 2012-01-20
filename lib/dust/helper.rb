# combines two arrays
# stolen from Juan Matias (jmrepetti) from stackoverflow.com
class Array
  def combine a
    return a if self.empty?
    return self if a.empty?

    aux = []
    self.each do |self_elem|
      a.each do |other_elem|
        aux << [ self_elem, other_elem ]
      end
    end
    aux.map {|elem| elem.flatten }
  end
end

class Hash
  # stole this from rails
  # Returns a new hash with +self+ and +other_hash+ merged recursively.
  def deep_merge(other_hash)
    dup.deep_merge!(other_hash)
  end

  # Returns a new hash with +self+ and +other_hash+ merged recursively.
  # Modifies the receiver in place.
  def deep_merge!(other_hash)
    other_hash.each_pair do |k,v|
      tv = self[k]
      self[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? tv.deep_merge(v) : v
    end
    self
  end

  
  # converts each value to an array, so .each and .combine won't get hickups
  def values_to_array!
    self.keys.each { |k| self[k] = [ self[k] ] unless self[k].is_a? Array }    
  end
  
  # converts each value that is a boolean to 'yes' resp. 'no' strings
  def boolean_to_string!
    self.each { |k, v| self[k] = v ? 'yes' : 'no' if v.is_a? TrueClass or v.is_a? FalseClass }
  end 
end


class String
  # stole this from Afz902k who posted something similar at stackoverflow.com
  # adds ability to check if a class with the name of a string exists  
  def to_class
    Kernel.const_get self.capitalize
  rescue NameError 
    nil
  end

  def is_a_defined_class?
    true if self.to_class
  rescue NameError
    false
  end
end


module Dust
  # converts string to kilobytes (rounded)
  def self.convert_size s
    i, unit = s.split(' ')
  
    case unit.downcase
    when 'kb'
      return i.to_i
    when 'mb'
      return (i.to_f * 1024).to_i
    when 'gb'
      return (i.to_f * 1024 * 1024).to_i
    when 'tb'
      return (i.to_f * 1024 * 1024 * 1024).to_i
    else
      return false
    end
  end
end
