# Codestitcher
# author Rahman Lavaee

class String
  def is_int?
    true if Integer(self) rescue false
  end
end

class Fixnum
	def is_page?
		eql?(64) || eql?(4 << 10) || eql?(2 << 20) 
	end
end
