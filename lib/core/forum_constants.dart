class ForumConstants {
  const ForumConstants._();

  static const host = 'bbs.shu.edu.cn';
  static const baseUrl = 'https://bbs.shu.edu.cn';
  static const postsPath = '/posts';
  static const postActionsPath = '/post_actions';

  /// Discourse 会话 Cookie，携带 OAuth CSRF state 与登录态。
  static const sessionCookieName = '_forum_session';
}
