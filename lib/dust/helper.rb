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

# stole this from rails
# https://github.com/rails/rails/blob/c0262827cacc1baf16668af65c35a09138166394/activesupport/lib/active_support/core_ext/hash/deep_merge.rb
class Hash
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
end

# stole this from Afz902k who posted something similar at stackoverflow.com
# adds ability to check if a class with the name of a string exists
class String
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
