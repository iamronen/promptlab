# frozen_string_literal: true

require "test_helper"

class ProjectPublicIdTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    Current.user = @user
  end

  test "assigns public_id on create" do
    project = Project.create!(name: "Public ID project", user: @user)

    assert project.public_id.present?
    assert_match(/\A[A-Za-z0-9_-]+\z/, project.public_id)
    assert_operator project.public_id.length, :>=, 20
  end

  test "public_id is globally unique" do
    first = Project.create!(name: "One", user: @user)
    second = Project.create!(name: "Two", user: @user)

    assert_not_equal first.public_id, second.public_id
  end

  test "to_param returns public_id" do
    project = Project.create!(name: "Test", user: @user)

    assert_equal project.public_id, project.to_param
  end

  test "find_by_public_id! locates project" do
    project = Project.create!(name: "Test", user: @user)

    found = Project.find_by_public_id!(project.public_id)
    assert_equal project.id, found.id
  end
end
