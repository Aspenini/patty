module Patty::Security::ConstantTime
  extend self

  def equal?(left : String, right : String) : Bool
    equal?(left.to_slice, right.to_slice)
  end

  def equal?(left : Bytes, right : Bytes) : Bool
    difference = left.size ^ right.size
    size = Math.max(left.size, right.size)
    size.times do |index|
      l = index < left.size ? left[index] : 0_u8
      r = index < right.size ? right[index] : 0_u8
      difference |= l ^ r
    end
    difference == 0
  end
end
