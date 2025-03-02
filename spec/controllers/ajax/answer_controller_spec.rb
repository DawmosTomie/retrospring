# coding: utf-8
# frozen_string_literal: true

require "rails_helper"

describe Ajax::AnswerController, :ajax_controller, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  let(:question) { FactoryBot.create(:question, user: FactoryBot.build(:user, privacy_allow_stranger_answers: asker_allows_strangers)) }
  let(:asker_allows_strangers) { true }

  describe "#create" do
    let(:params) do
      {
        id:,
        answer:,
        share:  shared_services&.to_json,
        inbox:,
      }.compact
    end

    subject { post(:create, params:) }

    context "when user is signed in" do
      shared_examples "creates the answer" do
        it "creates an answer" do
          expect { subject }.to(change { Answer.count }.by(1))
        end

        include_examples "returns the expected response"

        include_examples "touches user timestamp", :inbox_updated_at
      end

      shared_examples "does not create the answer" do
        it "does not create an answer" do
          expect { subject }.not_to(change { Answer.count })
        end

        include_examples "returns the expected response"
      end

      shared_examples "fails when answer content is empty" do
        let(:expected_response) do
          {
            "success" => false,
            # caught by rescue_from, so status is not peter_dinklage
            "status"  => "parameter_error",
            "message" => anything,
          }
        end

        ["", "    ", "\r  \n"].each do |a|
          context "when answer is #{a.inspect}" do
            let(:answer) { a }
            include_examples "does not create the answer"
          end
        end
      end

      before(:each) { sign_in(user) }

      context "when all parameters are given" do
        let(:answer) { "Werfen Sie nicht länger das Fenster zum Geld hinaus!" }
        let(:shared_services) { %w[twitter] }

        context "when inbox is true" do
          let(:id) { FactoryBot.create(:inbox, user: inbox_user, question:).id }
          let(:inbox) { true }

          context "when the inbox entry belongs to the user" do
            let(:inbox_user) { user }
            let(:expected_response) do
              {
                "success" => true,
                "status"  => "okay",
                "message" => anything,
              }
            end

            include_examples "creates the answer"

            it_behaves_like "fails when answer content is empty"

            context "when the user has sharing enabled" do
              before do
                user.sharing_enabled = true
                user.save
              end

              let(:expected_response) do
                super().merge(
                  "sharing" => {
                    "url"      => a_string_matching("https://#{APP_CONFIG['hostname']}/"),
                    "text"     => a_string_matching("Werfen Sie nicht länger das Fenster zum Geld hinaus!"),
                    "twitter"  => a_string_matching("https://twitter.com/"),
                    "tumblr"   => a_string_matching("https://www.tumblr.com/"),
                    "telegram" => a_string_matching("https://t.me/"),
                    "custom"   => a_string_matching(/Werfen\+Sie\+nicht\+l%C3%A4nger\+das\+Fenster\+zum\+Geld\+hinaus%21/),
                  }
                )
              end

              include_examples "creates the answer"
            end
          end

          context "when the inbox entry does not belong to the user" do
            let(:inbox_user) { FactoryBot.create(:user) }
            let(:expected_response) do
              {
                "success" => false,
                "status"  => "fail",
                "message" => anything,
              }
            end

            include_examples "does not create the answer"

            it_behaves_like "fails when answer content is empty"
          end

          context "when the question author mutes the user" do
            let(:inbox_user) { user }
            let(:expected_response) do
              {
                "success" => true,
                "status"  => "okay",
                "message" => anything,
              }
            end

            before do
              question.user.mute(inbox_user)
            end

            include_examples "creates the answer"

            it_behaves_like "fails when answer content is empty"

            it "does not create a notification for the question author" do
              expect { subject }.to change { question.user.notifications.count }.by(0)
            end
          end
        end

        context "when inbox is false" do
          let(:id) { question.id }
          let(:inbox) { false }

          context "when question asker allows strangers to answer (i.e. question was not in inbox)" do
            let(:asker_allows_strangers) { true }
            let(:expected_response) do
              {
                "success" => true,
                "status"  => "okay",
                "message" => anything,
                "render"  => anything,
              }
            end

            include_examples "creates the answer"

            it_behaves_like "fails when answer content is empty"

            context "when the user has sharing enabled" do
              before do
                user.sharing_enabled = true
                user.save
              end

              let(:expected_response) do
                super().merge(
                  "sharing" => {
                    "url"      => a_string_matching("https://#{APP_CONFIG['hostname']}/"),
                    "text"     => a_string_matching("Werfen Sie nicht länger das Fenster zum Geld hinaus!"),
                    "twitter"  => a_string_matching("https://twitter.com/"),
                    "tumblr"   => a_string_matching("https://www.tumblr.com/"),
                    "telegram" => a_string_matching("https://t.me/"),
                    "custom"   => a_string_matching(/Werfen\+Sie\+nicht\+l%C3%A4nger\+das\+Fenster\+zum\+Geld\+hinaus%21/),
                  }
                )
              end

              include_examples "creates the answer"
            end
          end

          context "when question asker does not allow strangers to answer (i.e. question was not in inbox)" do
            let(:asker_allows_strangers) { false }
            let(:expected_response) do
              {
                "success" => false,
                "status"  => "privacy_stronk",
                "message" => anything,
              }
            end

            include_examples "does not create the answer"
          end

          context "when user is blocked by the question author" do
            let!(:block) { Relationships::Block.create(source_id: question.user.id, target_id: user.id) }
            let(:shared_services) { %w[] }
            let(:answer) { "u suck >:3" }

            let(:expected_response) do
              {
                "success" => false,
                "status"  => "answering_other_blocked_self",
                "message" => I18n.t("errors.answering_other_blocked_self"),
              }
            end

            include_examples "returns the expected response"
          end

          context "when question author is blocked by the user" do
            let!(:block) { Relationships::Block.create(source_id: user.id, target_id: question.user.id) }
            let(:shared_services) { %w[] }
            let(:answer) { "u suck >:3" }

            let(:expected_response) do
              {
                "success" => false,
                "status"  => "answering_self_blocked_other",
                "message" => I18n.t("errors.answering_self_blocked_other"),
              }
            end

            include_examples "returns the expected response"
          end
        end
      end

      context "when some parameters are missing" do
        let(:id) { nil }
        let(:answer) { "Trollolo" }
        let(:inbox) { nil }
        let(:shared_services) { [] }

        let(:expected_response) do
          {
            "success" => false,
            # caught by rescue_from, so status is not peter_dinklage
            "status"  => "parameter_error",
            "message" => anything,
          }
        end

        include_examples "returns the expected response"
      end
    end

    context "when user is not signed in" do
      let(:id) { question.id }
      let(:inbox) { false }
      let(:shared_services) { %w[twitter] }
      let(:answer) { "HACKED" }

      let(:expected_response) do
        {
          "success" => false,
          "status"  => "err",
          "message" => anything,
        }
      end

      include_examples "returns the expected response"
    end
  end

  describe "#destroy" do
    let(:answer_user) { user }
    let(:question) { FactoryBot.create(:question) }
    let(:answer) { FactoryBot.create(:answer, user: answer_user, question:) }
    let(:answer_id) { answer.id }

    let(:params) do
      {
        answer: answer_id,
      }
    end

    subject { delete(:destroy, params:) }

    context "when user is signed in" do
      shared_examples "deletes the answer" do
        let(:expected_response) do
          {
            "success" => true,
            "status"  => "okay",
            "message" => anything,
          }
        end

        it "deletes the answer" do
          answer # ensure we already have it in the db
          expect { subject }.to(change { Answer.count }.by(-1))
        end

        include_examples "returns the expected response"
      end

      shared_examples "does not delete the answer" do
        let(:expected_response) do
          {
            "success" => false,
            "status"  => "nopriv",
            "message" => anything,
          }
        end

        it "does not delete the answer" do
          answer # ensure we already have it in the db
          expect { subject }.not_to(change { Answer.count })
        end

        include_examples "returns the expected response"
      end

      before(:each) { sign_in(user) }

      context "when the answer exists and was made by the current user" do
        include_examples "deletes the answer"

        it "returns the question back to the user's inbox" do
          expect { subject }.to(change { Inbox.where(question_id: answer.question.id, user_id: user.id).count }.by(1))
        end

        it "returns the question back to the user's inbox when the user has anonymous questions disabled" do
          user.privacy_allow_anonymous_questions = false
          user.save
          expect { subject }.to(change { Inbox.where(question_id: answer.question.id, user_id: user.id).count }.by(1))
        end

        it "updates the inbox caching timestamp for the user who answered" do
          initial_timestamp = 1.day.ago
          answer.user.update(inbox_updated_at: initial_timestamp)
          travel_to 1.day.from_now do
            # using string representation to avoid precision issues
            expect { subject }.to(change { answer.user.reload.inbox_updated_at.to_s }.from(initial_timestamp.to_s).to(DateTime.now))
          end
        end
      end

      context "when the answer exists and was not made by the current user" do
        let(:answer_user) { FactoryBot.create(:user) }
        include_examples "does not delete the answer"

        %i[moderator administrator].each do |privileged_role|
          context "when the current user is a #{privileged_role}" do
            around do |example|
              user.add_role privileged_role
              example.run
              user.remove_role privileged_role
            end

            include_examples "deletes the answer"
          end
        end
      end

      context "when the answer does not exist" do
        let(:answer_id) { "sonic_the_hedgehog" }

        let(:expected_response) do
          {
            "success" => false,
            "status"  => anything,
            "message" => anything,
          }
        end

        include_examples "returns the expected response"
      end
    end

    context "when user is not signed in" do
      let(:expected_response) do
        {
          "success" => false,
          "status"  => "nopriv",
          "message" => anything,
        }
      end

      include_examples "returns the expected response"
    end
  end
end
