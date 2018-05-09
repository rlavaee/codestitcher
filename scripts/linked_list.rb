# Codestitcher
# author Rahman Lavaee

class LinkedList
	attr_reader :head

	def initialize
		@head = nil
		@tail = nil
	end

	def prepend_val(val,cur=nil)
		if(!cur.nil?)
			remove_node(cur)
			prepend_node(cur)
		else
			node = ListNode.new(val)
			prepend_node(node)
		end
	end

	def append_val(val)
		node = ListNode.new(val)
		append_node(node)
	end

	
	def prepend_node(node) #add node to the beginning of the list
		if(@head.nil?)
			@head = @tail = node
		else
			@head.prev_node = node
			node.next_node = @head
			node.prev_node = nil
			@head = node
		end
	end

	def append_node(node) #add node to the end of the list
		if(@tail.nil?)
			@head = @tail = node
		else
			@tail.next_node = node
			node.prev_node = @tail
			node.next_node = nil
			@tail = node
		end
	end


	def remove_node(node)
		_prev = node.prev_node
		_next = node.next_node
		(_prev.nil?)?(@head = _next):(_prev.next_node = _next)
		(_next.nil?)?(@tail = _prev):(_next.prev_node = _prev)
	end

	def pop_head #removes the first element (head) from the list
		node = @head
		remove_node(node)
		node
	end

	def each
		node = @head
		while !node.nil?
			yield node
			node = node.next_node
		end
	end

	def inject(accumulator = 0 , &block)
		self.each {|item| accumulator = block.call(accumulator, item)}
		accumulator
	end

end

class ListNode
	attr_reader :value
	attr_accessor :next_node
	attr_accessor :prev_node

	def initialize(val)
		@value = val
		@next_node = nil
		@prev_node = nil
	end

end

=begin
list = LinkedList.new
list.prepend_val("everybody")
list.prepend_val("hello")
list.prepend_val("mina")
list.each {|x| puts x}
puts "------------"
list.each {|x| puts x}
list.prepend_val("hello")
puts "------------"
list.each {|x| puts x}
=end
