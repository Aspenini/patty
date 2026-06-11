require "html"

# Tiny template helpers, available inside ECR pages.

def h(text) : String
  HTML.escape(text.to_s)
end

def nl2br(text : String) : String
  HTML.escape(text).gsub("\n", "<br>")
end
