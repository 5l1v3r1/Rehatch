import Foundation
import SwiftCLI
import Twitter
import CSV

final class RehatchCommand: Command {
	enum Constant {
		static let consumerKey = ConsumerKey(
			key: "<CONSUMER_KEY>",
			secret: "<CONSUMER_SECRET>"
		)
	}

	let name = "rehatch"

	let twitterArchivePath = Parameter(
		completion: .none,
		validation: [.custom("file does not exist at specified path", { FileManager.default.fileExists(atPath: $0) })]
	)
	let untilDate = Key<Int>("--until-date", "-d", description: "UNIX date until which tweets are deleted")

	init() {}

	func execute() throws {
		let oauthApi = OAuth.API(consumerKey: Constant.consumerKey)
		let requestToken = try oauthApi.requestToken()
		let authorizationResponse = try oauthApi.authorize(with: requestToken)
		let accessToken = try oauthApi.exchangeRequestTokenForAccessToken(with: requestToken, authorizationResponse: authorizationResponse)

		let twitterArchiveFolderName = URL(fileURLWithPath: twitterArchivePath.value).deletingPathExtension().lastPathComponent
		let twitterArchiveFolderPathURL = FileManager.default.temporaryDirectory.appendingPathComponent(twitterArchiveFolderName)
		let twitterArchiveFolderPath = twitterArchiveFolderPathURL.path
		_ = try Task.capture(bash: "unzip -qq -o \(twitterArchivePath.value) -d \(twitterArchiveFolderPath)")

		let archive = try Archive(contentsOfFolder: twitterArchiveFolderPath)
		let tweetsToDelete: [Archive.Tweet]
		if let untilDateUnix = untilDate.value {
			tweetsToDelete = archive.tweets.sortedTweets(until: Date(timeIntervalSince1970: TimeInterval(untilDateUnix)))
		} else {
			tweetsToDelete = archive.tweets
		}
		let report = Archive.Tweet.DeletionReport(totalTweets: archive.tweets.count)
		let statusesAPI = StatusesAPI(consumerKey: Constant.consumerKey, accessToken: accessToken)

		Logger.info("Hey @\(accessToken.username)! You are about to delete \(tweetsToDelete.count) tweets.")
		guard Input.readBool(prompt: "Would you like to proceed? (y/n)") else {
			return
		}

		Logger.step(report.progressString, succeedPrevious: false)
		for tweet in tweetsToDelete {
			do {
				if tweet.isRetweet {
					try statusesAPI.unretweetTweet(with: tweet.id)
				} else {
					try statusesAPI.deleteTweet(with: tweet.id)
				}
				report.add(tweet, success: true)
			} catch {
				report.add(tweet, success: false)
			}

			if !report.didFinish {
				Logger.step(report.progressString, succeedPrevious: false)
			} else {
				Logger.succeed(report.endString)
			}
		}
	}
}
