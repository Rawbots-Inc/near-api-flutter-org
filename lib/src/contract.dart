import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:near_api_flutter/near_api_flutter.dart';
import 'package:near_api_flutter/src/constants.dart';
import 'package:near_api_flutter/src/models/action_types.dart';
import 'package:near_api_flutter/src/models/transaction_dto.dart';
import 'package:near_api_flutter/src/transaction_api/transaction_manager.dart';

/// Represents a contract entity: contractId, view methods, and change methods
class Contract {
  String contractId;

  Contract(this.contractId);

  Future<Map<dynamic, dynamic>> callFunction(
    Account callerAccount,
    String functionName,
    String functionArgs, [
    double nearAmount = 0.0,
    int gasFees = Constants.defaultGas,
  ]) async {
    final accessKey = await callerAccount.findAccessKey();
    accessKey.nonce++;

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
      accessKey: accessKey,
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
    return await callerAccount.provider
        .broadcastTransaction(encodedTransaction);
  }

  Future<Map<dynamic, dynamic>> callFunctionWithDeposit(
    Account callerAccount,
    String methodName,
    String methodArgs,
    Wallet wallet,
    double nearAmount,
    successURL,
    failureURL,
    approvalURL, [
    int gasFees = Constants.defaultGas,
  ]) async {
    final accessKey = await callerAccount.findAccessKey();
    accessKey.nonce++;

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
      accessKey: accessKey,
    );

    // Serialize Transaction
    Uint8List serializedTransaction =
        TransactionManager.serializeFunctionCallTransaction(transaction);

    // Sign with wallet if there is a deposit
    String transactionEncoded =
        TransactionManager.encodeSerialization(serializedTransaction);
    wallet.requestDepositApproval(
        transactionEncoded, successURL, failureURL, approvalURL);

    return {"Result": "Please follow wallet to approve transaction"};
  }

  /// Calls contract view functions
  Future<Map<dynamic, dynamic>> callViewFuntion(RPCProvider provider,
      String methodName, String methodArgs, int? blockId) async {
    List<int> bytes = utf8.encode(methodArgs);
    String base64MethodArgs = base64.encode(bytes);
    return await provider.callViewFunction(
        contractId, methodName, base64MethodArgs, blockId);
  }

  Future<Map<dynamic, dynamic>> callBlockFuntion(RPCProvider provider) async {
    return await provider.callBlockFunction(contractId);
  }
}
