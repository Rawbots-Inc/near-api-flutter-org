import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:near_api_flutter/near_api_flutter.dart';
import 'package:near_api_flutter/src/constants.dart';
import 'package:near_api_flutter/src/models/action_types.dart';
import 'package:near_api_flutter/src/models/transaction_dto.dart';
import 'package:near_api_flutter/src/transaction_api/transaction_manager.dart';

/// Represents a contract entity: contractId, view methods, and change methods
class Contract {
  String contractId;
  Account callerAccount; //account to sign change method transactions

  int _accessKeyTasks = 0;
  bool get _isAccessKeyBusy => _accessKeyTasks > 0;

  late AccessKey _accessKey;

  Contract(this.contractId, this.callerAccount) {
    _refreshAccessKey();

    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isAccessKeyBusy) {
        return;
      }

      _refreshAccessKey(timer.tick);
    });
  }

  void setCallerAccount(Account account) {
    callerAccount = account;
    return _refreshAccessKey();
  }

  void _refreshAccessKey([int? timerTick]) async {
    _accessKey = await callerAccount.findAccessKey();

    if (kDebugMode) {
      final log = timerTick != null
          ? {'nonce': _accessKey.nonce, 'tick': timerTick}
          : {'nonce': _accessKey.nonce};
    }
  }

  void _lockAccessKey() {
    _accessKeyTasks++;
  }

  void _releaseAccessKey() {
    _accessKeyTasks = max(_accessKeyTasks - 1, 0);
  }

  void _increaseNonce() {
    _accessKey.nonce++;

    if (kDebugMode) {
      print('Increase nonce: ${_accessKey.nonce}!');
    }
  }

  Future<Map<dynamic, dynamic>> callFunction(
    String functionName,
    String functionArgs, [
    double nearAmount = 0.0,
    int gasFees = Constants.defaultGas,
  ]) async {
    _lockAccessKey();
    _increaseNonce();

    String publicKey =
        KeyStore.publicKeyToString(callerAccount.keyPair.publicKey);

    Transaction transaction = Transaction(
      actionType: ActionType.functionCall,
      signer: callerAccount.accountId,
      publicKey: publicKey,
      nearAmount: nearAmount.toStringAsFixed(12),
      gasFees: gasFees,
      receiver: contractId,
      methodName: functionName,
      methodArgs: functionArgs,
      accessKey: _accessKey,
    );

    // Serialize Transaction
    Uint8List serializedTransaction =
        TransactionManager.serializeFunctionCallTransaction(transaction);
    Uint8List hashedSerializedTx =
        TransactionManager.toSHA256(serializedTransaction);

    // Sign Transaction
    Uint8List signature = TransactionManager.signTransaction(
        callerAccount.keyPair.privateKey, hashedSerializedTx);

    // Serialize Signed Transaction
    Uint8List serializedSignedTransaction =
        TransactionManager.serializeSignedFunctionCallTransaction(
            transaction, signature);
    String encodedTransaction =
        TransactionManager.encodeSerialization(serializedSignedTransaction);

    // Broadcast Transaction
    final resp =
        await callerAccount.provider.broadcastTransaction(encodedTransaction);

    _releaseAccessKey();

    return resp;
  }

  Future<Map<dynamic, dynamic>> callFunctionWithDeposit(
    String methodName,
    String methodArgs,
    Wallet wallet,
    double nearAmount,
    successURL,
    failureURL,
    approvalURL, [
    int gasFees = Constants.defaultGas,
  ]) async {
    _lockAccessKey();
    _increaseNonce();

    String publicKey =
        KeyStore.publicKeyToString(callerAccount.keyPair.publicKey);

    Transaction transaction = Transaction(
      actionType: ActionType.functionCall,
      signer: callerAccount.accountId,
      publicKey: publicKey,
      nearAmount: nearAmount.toStringAsFixed(12),
      gasFees: gasFees,
      receiver: contractId,
      methodName: methodName,
      methodArgs: methodArgs,
      accessKey: _accessKey,
    );

    // Serialize Transaction
    Uint8List serializedTransaction =
        TransactionManager.serializeFunctionCallTransaction(transaction);

    // Sign with wallet if there is a deposit
    String transactionEncoded =
        TransactionManager.encodeSerialization(serializedTransaction);
    wallet.requestDepositApproval(
        transactionEncoded, successURL, failureURL, approvalURL);

    _releaseAccessKey();

    return {"Result": "Please follow wallet to approve transaction"};
  }

  /// Calls contract view functions
  Future<Map<dynamic, dynamic>> callViewFuntion(
      String methodName, String methodArgs, int? blockId) async {
    List<int> bytes = utf8.encode(methodArgs);
    String base64MethodArgs = base64.encode(bytes);
    return await callerAccount.provider
        .callViewFunction(contractId, methodName, base64MethodArgs, blockId);
  }

  Future<Map<dynamic, dynamic>> callBlockFuntion() async {
    return await callerAccount.provider.callBlockFunction(contractId);
  }
}
