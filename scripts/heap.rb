# Codestitcher
# author Rahman Lavaee
class HeapNode
	@@count = 0
	attr_reader :id
	attr_accessor :parent
	attr_reader :heap
	attr_accessor :data
	attr_reader :children

	def initialize(arg)
		@id = @@count += 1
		@data = arg
		@parent = nil
		@children = Array.new(2,nil)
		@heap = nil
	end

	def left= node
		children[0] = node
	end

	def right= node
		children[1] = node
	end

	def left
		children[0]
	end

	def right
		children[1]
	end

	def adopt_left node
		self.left = node
		node.parent = self if(!node.nil?)
	end

	def adopt_right node
		self.right = node
		node.parent = self if(!node.nil?)
	end

	def adopt_children new_children
		adopt_left new_children[0]
		adopt_right new_children[1]
	end

	def is_left_child?
		(@parent.nil?)?(false):(@parent.left==self)
	end

	def is_right_child?
		(@parent.nil?)?(false):(@parent.right==self)
	end
	def < node
		(@data == node.data)?(@id < node.id):((@data <=> node.data) == -1)
	end

	def <=> node
		(@data == node.data)? (@id <=> node.id) :(@data <=> node.data)
	end

	def attached?(h)
		@heap == h
	end

	def detach
		@heap = nil	
		@children = [nil,nil]
		@parent = nil
	end

	def attach(heap)
		@heap = heap
	end


	def swap_with_parent
		par = @parent
		raise "parent is nil" if(par.nil?)
		gpar = par.parent
		if(!gpar.nil?)
			(par.is_left_child?)?(gpar.adopt_left(self)):(gpar.adopt_right(self))
		else
			raise "parent is not root" if(@heap.root!=par)
			@heap.assign_root(self)
		end

		par_old_left = par.left
		par_old_right = par.right

		par.adopt_children(@children)
		(par_old_left==self) ? (adopt_children([par,par_old_right])) : (adopt_children([par_old_left,par]))
	end

	def heapify_up
		if(!@parent.nil? && @parent < self)
			swap_with_parent
			heapify_up
		end
	end

	def heapify_down
		max_child = @children.reject{|child| child.nil?}.max
		if(!max_child.nil? && self < max_child)
			max_child.swap_with_parent
			heapify_down
		end
	end


	def fixup
		heapify_up
		heapify_down
	end

	
	def get_node_with_handle(handle)
		#puts "handle is #{handle}, node is #{self} -> left: #{left} , right: #{right}"
		if(handle==1)
			self
		else
			node = get_node_with_handle(handle >> 1)
			(handle & 1==1)?(node.right):(node.left)
		end
	end

	def inspect_helper(level)
		([@data.to_s] + @children.map {|child| '  '*level + ((child.nil?)?("NIL"):(child.inspect_helper(level+1)))}).join("\n")
	end

	def to_s
		"["+ @id.to_s + ":" + @data.to_s + "]"
	end
	
end

class Heap
	attr_reader :root

	def initialize
		@root = nil
		@size = 0
	end

	def empty?
		@size==0
	end

	def assign_root new_root
		@root = new_root
		@root.parent=nil if(!@root.nil?)
	end


	def insert (node)
		raise "node is already attached to this heap" if(node.attached?(self))
		node.attach(self)
		if(@root.nil?)
			assign_root(node)
		else
			handle = @size + 1
			par = @root.get_node_with_handle(handle >> 1)
			(handle & 1==1)? (par.adopt_right(node)): (par.adopt_left(node))
			node.heapify_up
		end
		@size+=1
	end

	def remove (node)
			#puts "removing node: #{node.data.inspect}"
			raise "node is not attached to this heap" if(!node.attached?(self))
			raise "heap is empty" if(@root.nil?)
			last = @root.get_node_with_handle(@size)
			raise "children are not nil" if(!last.left.nil? || !last.right.nil?)
			node_par = node.parent
			last_par = last.parent
			
			
			#detach last from its parent
			((last.is_left_child?)? (last.parent.left=nil) : (last.parent.right=nil)) if(!last.parent.nil?)

			if(node!=last)
				if(node.parent.nil?) 
					raise "node is not root" if(node!=@root)
					assign_root(last)
				else
					(node.is_left_child?)? (node.parent.adopt_left(last)) : (node.parent.adopt_right(last))
				end
				
				last.adopt_children(node.children)
				last.fixup
			elsif node.parent.nil?
				raise "node is not root" if(node!=@root)
				assign_root(nil)
			end

			@size-=1
			node.detach
	end

	def pop
		old_root = @root
		remove(@root) if(!@root.nil?)
		old_root
	end

	def inspect
		["<"*10+" size:#{@size}",(@root.nil?)? ("NULL HEAP") : (@root.inspect_helper(1)), ">"*10].join("\n")
	end

end

=begin
heap = Heap.new
nodes = [1,4,7,9,6,5].map{|i| HeapNode.new(i)}
nodes.each {|n| heap.insert(n); puts heap.inspect}

while(!heap.empty?)
	puts heap.inspect
	puts heap.pop.data
end
=end
