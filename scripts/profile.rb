# Codestitcher
# author Rahman Lavaee

require 'fileutils'

class Profile < Hash
	attr_reader :prof_dso
	attr_accessor :updated

	def load_from_symbols(exe_file_path)
		@prof_dso = DSO.new(exe_file_path)
		puts "reading exe syms for: #{exe_file_path}"
		IO.popen("#{LLVM_BIN} --numeric-sort --print-size #{exe_file_path}","r") do |nm_pipe|
			nm_pipe.each_line do |line|
				tokens = line.chomp.gsub(/\s+/m,' ').strip.split(" ")
				tokens[-1] = tokens[-1].strip
				if(tokens.length>=4)
					bb_args = tokens.last.split(/[*-]/)
					if(bb_args.length>1)
						bb_args << "NOLP" if(bb_args.last!="LP")
						bb_args << tokens[0] << tokens[1]
						@prof_dso.get_or_add_basic_block(bb_args)
					end
				end
			end
			@prof_dso.set_func_succs
			@prof_dso.set_landing_pads
		end
		puts "reading exe syms completed"
	end



	def Profile.load_agg_profile(exe_file_path)
		dump_file_path = exe_file_path+".profile.agg.dump"
		if File.exists?(dump_file_path+".gz")
			system("gunzip -c #{dump_file_path}.gz > #{dump_file_path}")
			puts "LOADING....."
			return File.open(dump_file_path,"r") {|df| Marshal.load(df)}
		else
			puts "dump does not exist"
			nil
		end
	end


	def dump_prof_to_file
		puts "DUMPING....."
		dump_file_path = @prof_dso.path+".profile.agg.dump"
		File.open(dump_file_path,"w") { |df| Marshal.dump(@prof_dso,df)}
		`gzip -f #{dump_file_path}`
		puts "DUMPING.....END"
	end

end
