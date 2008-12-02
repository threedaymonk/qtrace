if Rails.env == 'development' then
  require File.join(File.dirname(__FILE__), 'lib', 'qtrace')
else
  require File.join(File.dirname(__FILE__), 'lib', 'qtrace', 'stub')
end
