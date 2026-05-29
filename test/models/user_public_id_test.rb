# frozen_string_literal: true

require "test_helper"

class UserPublicIdTest < ActiveSupport::TestCase
  test "assigns public_id on create" do
    user = User.create!(
      email: "public-id-user@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    assert user.public_id.present?
    assert_match(/\A[A-Za-z0-9_-]+\z/, user.public_id)
    assert_operator user.public_id.length, :>=, 20
  end

  test "public_id is globally unique" do
    first = User.create!(
      email: "public-id-one@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    second = User.create!(
      email: "public-id-two@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    assert_not_equal first.public_id, second.public_id
  end

  test "to_param returns public_id" do
    user = users(:alice)

    assert_equal user.public_id, user.to_param
  end

  test "find_by_public_id! locates user" do
    user = users(:alice)

    found = User.find_by_public_id!(user.public_id)
    assert_equal user.id, found.id
  end
end
