class RemoteNodeAuthSession {
  final String contactKeyHex;
  final String password;
  final bool isAdmin;
  final DateTime authenticatedAt;

  const RemoteNodeAuthSession({
    required this.contactKeyHex,
    required this.password,
    required this.isAdmin,
    required this.authenticatedAt,
  });

  RemoteNodeAuthSession copyWith({
    String? password,
    bool? isAdmin,
    DateTime? authenticatedAt,
  }) {
    return RemoteNodeAuthSession(
      contactKeyHex: contactKeyHex,
      password: password ?? this.password,
      isAdmin: isAdmin ?? this.isAdmin,
      authenticatedAt: authenticatedAt ?? this.authenticatedAt,
    );
  }
}
