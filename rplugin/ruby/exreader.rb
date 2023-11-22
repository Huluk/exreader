Neovim.plugin do |plug|
  plug.command(:P, range: true, nargs: '*') do |
    nvim,
    *args,
    range_begin,
    range_end
  |
    position = nvim.current.window.cursor
    p_cmd = "#{range_begin},#{range_end}p#{args.join(' ')}"
    p_output = nvim.command_output(p_cmd) # read lines
    system 'say', p_output
    nvim.current.window.cursor = position
    nvim.command(p_cmd) # also generate output
  end
end
