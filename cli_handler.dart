import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:collection/collection.dart';
import 'package:convert/convert.dart';
import 'package:dcli/dcli.dart';
import 'package:path/path.dart' as path;
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'init_znn.dart';

Future<int> main(List<String> args) async {
  return initZnn(args, handleCli);
}

Future<void> handleCli(List<String> args) async {
  final Zenon znnClient = Zenon();
  Address? address = (await znnClient.defaultKeyPair?.address);

  switch (args[0]) {
    case 'version':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('version');
        break;
      }
      print('$znnCli v$znnCliVersion using Zenon SDK v$znnSdkVersion');
      print(getZnndVersion());
      break;

    case 'send':
      if (!(args.length == 4 || args.length == 5)) {
        print('Incorrect number of arguments. Expected:');
        print(
            'send toAddress amount [${green('ZNN')}/${blue('QSR')}/${magenta('ZTS')}]');
        break;
      }
      Address newAddress = Address.parse(args[1]);
      late int amount;
      TokenStandard tokenStandard;
      if (args[3] == 'znn' || args[3] == 'ZNN') {
        tokenStandard = znnZts;
      } else if (args[3] == 'qsr' || args[3] == 'QSR') {
        tokenStandard = qsrZts;
      } else {
        tokenStandard = TokenStandard.parse(args[3]);
      }

      AccountInfo info =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      bool ok = true;
      bool found = false;
      for (BalanceInfoListItem entry in info.balanceInfoList!) {
        if (entry.token!.tokenStandard.toString() == tokenStandard.toString()) {
          amount =
              (double.parse(args[2]) * entry.token!.decimalsExponent()).round();
          if (entry.balance! < amount) {
            print(
                '${red("Error!")} You only have ${formatAmount(entry.balance!, entry.token!.decimals)} ${entry.token!.symbol} tokens');
            ok = false;
            break;
          }
          found = true;
        }
      }

      if (!ok) break;
      if (!found) {
        print(
            '${red("Error!")} You only have ${formatAmount(0, 0)} ${tokenStandard.toString()} tokens');
        break;
      }
      Token? token = await znnClient.embedded.token.getByZts(tokenStandard);
      var block = AccountBlockTemplate.send(newAddress, tokenStandard, amount);

      if (args.length == 5) {
        block.data = AsciiEncoder().convert(args[4]);
        print(
            'Sending ${formatAmount(amount, token!.decimals)} ${args[3]} to ${args[1]} with a message "${args[4]}"');
      } else {
        print(
            'Sending ${formatAmount(amount, token!.decimals)} ${args[3]} to ${args[1]}');
      }

      await znnClient.send(block);
      print('Done');
      break;

    case 'receive':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('receive blockHash');
        break;
      }
      Hash sendBlockHash = Hash.parse(args[1]);
      print('Please wait ...');
      await znnClient.send(AccountBlockTemplate.receive(sendBlockHash));
      print('Done');
      break;

    case 'receiveAll':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('receiveAll');
        break;
      }
      var unreceived = (await znnClient.ledger
          .getUnreceivedBlocksByAddress(address!, pageIndex: 0, pageSize: 5));
      if (unreceived.count == 0) {
        print('Nothing to receive');
        break;
      } else {
        if (unreceived.more!) {
          print(
              'You have ${red("more")} than ${green(unreceived.count.toString())} transaction(s) to receive');
        } else {
          print(
              'You have ${green(unreceived.count.toString())} transaction(s) to receive');
        }
      }

      print('Please wait ...');
      while (unreceived.count! > 0) {
        for (var block in unreceived.list!) {
          await znnClient.send(AccountBlockTemplate.receive(block.hash));
        }
        unreceived = (await znnClient.ledger
            .getUnreceivedBlocksByAddress(address, pageIndex: 0, pageSize: 5));
      }
      print('Done');
      break;

    case 'autoreceive':
      znnClient.wsClient
          .addOnConnectionEstablishedCallback((broadcaster) async {
        print('Subscribing for account-block events ...');
        await znnClient.subscribe.toAllAccountBlocks();
        print('Subscribed successfully!');

        broadcaster.listen((json) async {
          if (json!['method'] == 'ledger.subscription') {
            for (var i = 0; i < json['params']['result'].length; i += 1) {
              var tx = json['params']['result'][i];
              if (tx['toAddress'] != address.toString()) {
                continue;
              }
              var hash = tx['hash'];
              print('receiving transaction with hash $hash');
              var template = await znnClient
                  .send(AccountBlockTemplate.receive(Hash.parse(hash)));
              print(
                  'successfully received $hash. Receive-block-hash ${template.hash}');
              await Future.delayed(Duration(seconds: 1));
            }
          }
        });
      });

      for (;;) {
        await Future.delayed(Duration(seconds: 1));
      }

    case 'unreceived':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('unreceived');
        break;
      }
      var unreceived = await znnClient.ledger
          .getUnreceivedBlocksByAddress(address!, pageIndex: 0, pageSize: 5);

      if (unreceived.count == 0) {
        print('Nothing to receive');
      } else {
        if (unreceived.more!) {
          print(
              'You have ${red("more")} than ${green(unreceived.count.toString())} transaction(s) to receive');
        } else {
          print(
              'You have ${green(unreceived.count.toString())} transaction(s) to receive');
        }
        print('Showing the first ${unreceived.list!.length}');
      }

      for (var block in unreceived.list!) {
        print(
            'Unreceived ${formatAmount(block.amount, block.token!.decimals)} ${block.token!.symbol} from ${block.address.toString()}. Use the hash ${block.hash} to receive');
      }
      break;

    case 'unconfirmed':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('unconfirmed');
        break;
      }
      var unconfirmed = await znnClient.ledger
          .getUnconfirmedBlocksByAddress(address!, pageIndex: 0, pageSize: 5);

      if (unconfirmed.count == 0) {
        print('No unconfirmed transactions');
      } else {
        print(
            'You have ${green(unconfirmed.count.toString())} unconfirmed transaction(s)');
        print('Showing the first ${unconfirmed.list!.length}');
      }

      var encoder = JsonEncoder.withIndent('     ');
      for (var block in unconfirmed.list!) {
        print(encoder.convert(block.toJson()));
      }
      break;

    case 'balance':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('balance');
        break;
      }
      AccountInfo info =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      print(
          'Balance for account-chain ${info.address!.toString()} having height ${info.blockCount}');
      if (info.balanceInfoList!.isEmpty) {
        print('  No coins or tokens at address ${address.toString()}');
      }
      for (BalanceInfoListItem entry in info.balanceInfoList!) {
        print(
            '  ${formatAmount(entry.balance!, entry.token!.decimals)} ${entry.token!.symbol} '
            '${entry.token!.domain} ${entry.token!.tokenStandard.toString()}');
      }
      break;

    case 'frontierMomentum':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('frontierMomentum');
        break;
      }
      Momentum currentFrontierMomentum =
          await znnClient.ledger.getFrontierMomentum();
      print('Momentum height: ${currentFrontierMomentum.height.toString()}');
      print('Momentum hash: ${currentFrontierMomentum.hash.toString()}');
      print(
          'Momentum previousHash: ${currentFrontierMomentum.previousHash.toString()}');
      print(
          'Momentum timestamp: ${currentFrontierMomentum.timestamp.toString()}');
      break;

    case 'plasma.fuse':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('plasma.fuse toAddress amount (in ${blue('QSR')})');
        break;
      }
      Address beneficiary = Address.parse(args[1]);
      int amount = (double.parse(args[2]) * oneQsr).round();
      if (amount < fuseMinQsrAmount) {
        print(
            '${red('Invalid amount')}: ${formatAmount(amount, qsrDecimals)} ${blue('QSR')}. Minimum staking amount is ${formatAmount(fuseMinQsrAmount, qsrDecimals)}');
        break;
      } else if (amount % oneQsr != 0) {
        print('${red('Error!')} Amount has to be integer');
        break;
      }
      print(
          'Fusing ${formatAmount(amount, qsrDecimals)} ${blue('QSR')} to ${args[1]}');
      await znnClient.send(znnClient.embedded.plasma.fuse(beneficiary, amount));
      print('Done');
      break;

    case 'plasma.get':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('plasma.get');
        break;
      }
      PlasmaInfo plasmaInfo = await znnClient.embedded.plasma.get(address!);
      print(
          '${green(address.toString())} has ${plasmaInfo.currentPlasma} / ${plasmaInfo.maxPlasma}'
          ' plasma with ${formatAmount(plasmaInfo.qsrAmount, qsrDecimals)} ${blue('QSR')} fused.');
      break;

    case 'plasma.list':
      if (!(args.length == 1 || args.length == 3)) {
        print('Incorrect number of arguments. Expected:');
        print('plasma.list [pageIndex pageSize]');
        break;
      }
      int pageIndex = 0;
      int pageSize = 25;
      if (args.length == 3) {
        pageIndex = int.parse(args[1]);
        pageSize = int.parse(args[2]);
      }
      FusionEntryList fusionEntryList = (await znnClient.embedded.plasma
          .getEntriesByAddress(address!,
              pageIndex: pageIndex, pageSize: pageSize));

      if (fusionEntryList.count > 0) {
        print(
            'Fusing ${formatAmount(fusionEntryList.qsrAmount, qsrDecimals)} ${blue('QSR')} for Plasma in ${fusionEntryList.count} entries');
      } else {
        print('No Plasma fusion entries found');
      }

      for (FusionEntry entry in fusionEntryList.list) {
        print(
            '  ${formatAmount(entry.qsrAmount, qsrDecimals)} ${blue('QSR')} for ${entry.beneficiary.toString()}');
        print(
            'Can be canceled at momentum height: ${entry.expirationHeight}. Use id ${entry.id} to cancel');
      }
      break;

    case 'plasma.cancel':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('plasma.cancel id');
        break;
      }
      Hash id = Hash.parse(args[1]);

      int pageIndex = 0;
      bool found = false;
      bool gotError = false;

      FusionEntryList fusions =
          await znnClient.embedded.plasma.getEntriesByAddress(address!);
      while (fusions.list.isNotEmpty) {
        var index = fusions.list.indexWhere((entry) => entry.id == id);
        if (index != -1) {
          found = true;
          if (fusions.list[index].expirationHeight >
              (await znnClient.ledger.getFrontierMomentum()).height) {
            print('${red('Error!')} Fuse entry can not be cancelled yet');
            gotError = true;
          }
          break;
        }
        pageIndex++;
        fusions = await znnClient.embedded.plasma
            .getEntriesByAddress(address, pageIndex: pageIndex);
      }

      if (!found) {
        print('${red('Error!')} Fuse entry was not found');
        break;
      }
      if (gotError) {
        break;
      }
      print('Canceling Plasma fuse entry with id ${args[1]}');
      await znnClient.send(znnClient.embedded.plasma.cancel(id));
      print('Done');
      break;

    case 'sentinel.list':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('sentinel.list');
        break;
      }
      SentinelInfoList sentinels =
          (await znnClient.embedded.sentinel.getAllActive());
      bool one = false;
      for (SentinelInfo entry in sentinels.list) {
        if (entry.owner.toString() == address!.toString()) {
          if (entry.isRevocable) {
            print(
                'Revocation window will close in ${formatDuration(entry.revokeCooldown)}');
          } else {
            print(
                'Revocation window will open in ${formatDuration(entry.revokeCooldown)}');
          }
          one = true;
        }
      }
      if (!one) {
        print('No Sentinel registered at address ${address!.toString()}');
      }
      break;

    case 'sentinel.register':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('sentinel.register');
        break;
      }
      AccountInfo accountInfo =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      var depositedQsr =
          await znnClient.embedded.sentinel.getDepositedQsr(address);
      print('You have $depositedQsr ${blue('QSR')} deposited for the Sentinel');
      if (accountInfo.znn()! < sentinelRegisterZnnAmount ||
          accountInfo.qsr()! < sentinelRegisterQsrAmount) {
        print('Cannot register Sentinel with address ${address.toString()}');
        print(
            'Required ${formatAmount(sentinelRegisterZnnAmount, znnDecimals)} ${green('ZNN')} and ${formatAmount(sentinelRegisterQsrAmount, qsrDecimals)} ${blue('QSR')}');
        print(
            'Available ${formatAmount(accountInfo.znn()!, znnDecimals)} ${green('ZNN')} and ${formatAmount(accountInfo.qsr()!, qsrDecimals)} ${blue('QSR')}');
        break;
      }

      if (depositedQsr < sentinelRegisterQsrAmount) {
        await znnClient.send(znnClient.embedded.sentinel
            .depositQsr(sentinelRegisterQsrAmount - depositedQsr));
      }
      await znnClient.send(znnClient.embedded.sentinel.register());
      print('Done');
      print(
          'Check after 2 momentums if the Sentinel was successfully registered using ${green('sentinel.list')} command');
      break;

    case 'sentinel.revoke':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('sentinel.revoke');
        break;
      }
      SentinelInfo? entry = await znnClient.embedded.sentinel
          .getByOwner(address!)
          .catchError((e) {
        if (e.toString().contains('data non existent')) {
          return null;
        } else {
          print('Error: ${e.toString()}');
        }
      });

      if (entry == null) {
        print('No Sentinel found for address ${address.toString()}');
        break;
      }

      if (entry.isRevocable == false) {
        print(
            'Cannot revoke Sentinel. Revocation window will open in ${formatDuration(entry.revokeCooldown)}');
        break;
      }

      await znnClient.send(znnClient.embedded.sentinel.revoke());
      print('Done');
      print(
          'Use ${green('receiveAll')} to collect back the locked amount of ${green('ZNN')} and ${blue('QSR')}');
      break;

    case 'sentinel.collect':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('sentinel.collect');
        break;
      }
      await znnClient.send(znnClient.embedded.sentinel.collectReward());
      print('Done');
      print(
          'Use ${green('receiveAll')} to collect your Sentinel reward(s) after 1 momentum');
      break;

    case 'sentinel.withdrawQsr':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('sentinel.withdrawQsr');
        break;
      }

      int? depositedQsr =
          await znnClient.embedded.sentinel.getDepositedQsr(address!);
      if (depositedQsr == 0) {
        print('No deposited ${blue('QSR')} to withdraw');
        break;
      }
      print(
          'Withdrawing ${formatAmount(depositedQsr, qsrDecimals)} ${blue('QSR')} ...');
      await znnClient.send(znnClient.embedded.sentinel.withdrawQsr());
      print('Done');
      break;

    case 'stake.list':
      if (!(args.length == 1 || args.length == 3)) {
        print('Incorrect number of arguments. Expected:');
        print(' stake.list [pageIndex pageSize]');
        break;
      }
      int pageIndex = 0;
      int pageSize = 25;
      if (args.length == 3) {
        pageIndex = int.parse(args[1]);
        pageSize = int.parse(args[2]);
      }
      final currentTime =
          (DateTime.now().millisecondsSinceEpoch / 1000).round();
      StakeList stakeList = await znnClient.embedded.stake.getEntriesByAddress(
          address!,
          pageIndex: pageIndex,
          pageSize: pageSize);

      if (stakeList.count > 0) {
        print(
            'Showing ${stakeList.list.length} out of a total of ${stakeList.count} staking entries');
      } else {
        print('No staking entries found');
      }

      for (StakeEntry entry in stakeList.list) {
        print(
            'Stake id ${entry.id.toString()} with amount ${formatAmount(entry.amount, znnDecimals)} ${green('ZNN')}');
        if (entry.expirationTimestamp > currentTime) {
          print(
              '    Can be revoked in ${formatDuration(entry.expirationTimestamp - currentTime)}');
        } else {
          print('    ${green('Can be revoked now')}');
        }
      }
      break;

    case 'stake.register':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('stake.register amount duration (in months)');
        break;
      }
      final amount = (double.parse(args[1]) * oneZnn).round();
      final duration = int.parse(args[2]);
      if (duration < 1 || duration > 12) {
        print(
            '${red('Invalid duration')}: ($duration) $stakeUnitDurationName. It must be between 1 and 12');
        break;
      }
      if (amount < stakeMinZnnAmount) {
        print(
            '${red('Invalid amount')}: ${formatAmount(amount, znnDecimals)} ${green('ZNN')}. Minimum staking amount is ${formatAmount(stakeMinZnnAmount, znnDecimals)}');
        break;
      }
      AccountInfo balance =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      if (balance.znn()! < amount) {
        print(red('Not enough ZNN to stake'));
        break;
      }

      print(
          'Staking ${formatAmount(amount, znnDecimals)} ${green('ZNN')} for $duration $stakeUnitDurationName(s)');
      await znnClient.send(
          znnClient.embedded.stake.stake(stakeTimeUnitSec * duration, amount));
      print('Done');
      break;

    case 'stake.revoke':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('stake.revoke id');
        break;
      }
      Hash hash = Hash.parse(args[1]);

      final currentTime =
          (DateTime.now().millisecondsSinceEpoch / 1000).round();
      int pageIndex = 0;
      bool one = false;
      bool gotError = false;

      StakeList entries = await znnClient.embedded.stake
          .getEntriesByAddress(address!, pageIndex: pageIndex);
      while (entries.list.isNotEmpty) {
        for (StakeEntry entry in entries.list) {
          if (entry.id.toString() == hash.toString()) {
            if (entry.expirationTimestamp > currentTime) {
              print(
                  '${red('Cannot revoke!')} Try again in ${formatDuration(entry.expirationTimestamp - currentTime)}');
              gotError = true;
            }
            one = true;
          }
        }
        pageIndex++;
        entries = await znnClient.embedded.stake
            .getEntriesByAddress(address, pageIndex: pageIndex);
      }

      if (gotError) {
        break;
      } else if (!one) {
        print(
            '${red('Error!')} No stake entry found with id ${hash.toString()}');
        break;
      }

      await znnClient.send(znnClient.embedded.stake.cancel(hash));
      print('Done');
      print(
          'Use ${green('receiveAll')} to collect your stake amount and uncollected reward(s) after 2 momentums');
      break;

    case 'stake.collect':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('stake.collect');
        break;
      }
      await znnClient.send(znnClient.embedded.stake.collectReward());
      print('Done');
      print(
          'Use ${green('receiveAll')} to collect your stake reward(s) after 1 momentum');
      break;

    case 'pillar.list':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.list');
        break;
      }
      PillarInfoList pillarList = (await znnClient.embedded.pillar.getAll());
      for (PillarInfo pillar in pillarList.list) {
        print(
            '#${pillar.rank + 1} Pillar ${green(pillar.name)} has a delegated weight of ${formatAmount(pillar.weight, znnDecimals)} ${green('ZNN')}');
        print('    Producer address ${pillar.producerAddress}');
        print(
            '    Momentums ${pillar.currentStats.producedMomentums} / expected ${pillar.currentStats.expectedMomentums}');
      }
      break;

    case 'pillar.register':
      if (args.length != 6) {
        print('Incorrect number of arguments. Expected:');
        print(
            'pillar.register name producerAddress rewardAddress giveBlockRewardPercentage giveDelegateRewardPercentage');
        break;
      }

      int giveBlockRewardPercentage = int.parse(args[4]);
      int giveDelegateRewardPercentage = int.parse(args[5]);

      AccountInfo balance =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      int? qsrAmount =
          (await znnClient.embedded.pillar.getQsrRegistrationCost());
      int? depositedQsr =
          await znnClient.embedded.pillar.getDepositedQsr(address);
      if ((balance.znn()! < pillarRegisterZnnAmount ||
              balance.qsr()! < qsrAmount) &&
          qsrAmount > depositedQsr) {
        print('Cannot register Pillar with address ${address.toString()}');
        print(
            'Required ${formatAmount(pillarRegisterZnnAmount, znnDecimals)} ${green('ZNN')} and ${formatAmount(qsrAmount, qsrDecimals)} ${blue('QSR')}');
        print(
            'Available ${formatAmount(balance.znn()!, znnDecimals)} ${green('ZNN')} and ${formatAmount(balance.qsr()!, qsrDecimals)} ${blue('QSR')}');
        break;
      }

      print(
          'Creating a new ${green('Pillar')} will burn the deposited ${blue('QSR')} required for the Pillar slot');
      if (!confirm('Do you want to proceed?', defaultValue: false)) break;

      String newName = args[1];
      bool ok =
          (await znnClient.embedded.pillar.checkNameAvailability(newName));
      while (!ok) {
        newName = ask(
            'This Pillar name is already reserved. Please choose another name for the Pillar');
        ok = (await znnClient.embedded.pillar.checkNameAvailability(newName));
      }
      if (depositedQsr < qsrAmount) {
        print(
            'Depositing ${formatAmount(qsrAmount - depositedQsr, qsrDecimals)} ${blue('QSR')} for the Pillar registration');
        await znnClient.send(
            znnClient.embedded.pillar.depositQsr(qsrAmount - depositedQsr));
      }
      print('Registering Pillar ...');
      await znnClient.send(znnClient.embedded.pillar.register(
          newName,
          Address.parse(args[2]),
          Address.parse(args[3]),
          giveBlockRewardPercentage,
          giveDelegateRewardPercentage));
      print('Done');
      print(
          'Check after 2 momentums if the Pillar was successfully registered using ${green('pillar.list')} command');
      break;

    case 'pillar.collect':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.collect');
        break;
      }
      await znnClient.send(znnClient.embedded.pillar.collectReward());
      print('Done');
      print(
          'Use ${green('receiveAll')} to collect your Pillar reward(s) after 1 momentum');
      break;

    case 'pillar.revoke':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.revoke name');
        break;
      }
      PillarInfoList pillarList = (await znnClient.embedded.pillar.getAll());
      bool ok = false;
      for (PillarInfo pillar in pillarList.list) {
        if (args[1].compareTo(pillar.name) == 0) {
          ok = true;
          if (pillar.isRevocable) {
            print('Revoking Pillar ${pillar.name} ...');
            await znnClient.send(znnClient.embedded.pillar.revoke(args[1]));
            print(
                'Use ${green('receiveAll')} to collect back the locked amount of ${green('ZNN')}');
          } else {
            print(
                'Cannot revoke Pillar ${pillar.name}. Revocation window will open in ${formatDuration(pillar.revokeCooldown)}');
          }
        }
      }
      if (ok) {
        print('Done');
      } else {
        print('There is no Pillar with this name');
      }
      break;

    case 'pillar.delegate':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.delegate name');
        break;
      }
      print('Delegating to Pillar ${args[1]} ...');
      await znnClient.send(znnClient.embedded.pillar.delegate(args[1]));
      print('Done');
      break;

    case 'pillar.undelegate':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.undelegate');
        break;
      }

      print('Undelegating ...');
      await znnClient.send(znnClient.embedded.pillar.undelegate());
      print('Done');
      break;

    case 'pillar.withdrawQsr':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('pillar.withdrawQsr');
        break;
      }
      int? depositedQsr =
          await znnClient.embedded.pillar.getDepositedQsr(address!);
      if (depositedQsr == 0) {
        print('No deposited ${blue('QSR')} to withdraw');
        break;
      }
      print(
          'Withdrawing ${formatAmount(depositedQsr, qsrDecimals)} ${blue('QSR')} ...');
      await znnClient.send(znnClient.embedded.pillar.withdrawQsr());
      print('Done');
      break;

    case 'token.list':
      if (!(args.length == 1 || args.length == 3)) {
        print('Incorrect number of arguments. Expected:');
        print('token.list [pageIndex pageSize]');
        break;
      }
      int pageIndex = 0;
      int pageSize = 25;
      if (args.length == 3) {
        pageIndex = int.parse(args[1]);
        pageSize = int.parse(args[2]);
      }
      TokenList tokenList = await znnClient.embedded.token
          .getAll(pageIndex: pageIndex, pageSize: pageSize);
      for (Token token in tokenList.list!) {
        if (token.tokenStandard == znnZts || token.tokenStandard == qsrZts) {
          print(
              '${token.tokenStandard == znnZts ? green(token.name) : blue(token.name)} with symbol ${token.tokenStandard == znnZts ? green(token.symbol) : blue(token.symbol)} and standard ${token.tokenStandard == znnZts ? green(token.tokenStandard.toString()) : blue(token.tokenStandard.toString())}');
          print(
              '   Created by ${token.tokenStandard == znnZts ? green(token.owner.toString()) : blue(token.owner.toString())}');
          print(
              '   ${token.tokenStandard == znnZts ? green(token.name) : blue(token.name)} has ${token.decimals} decimals, ${token.isMintable ? 'is mintable' : 'is not mintable'}, ${token.isBurnable ? 'can be burned' : 'cannot be burned'}, and ${token.isUtility ? 'is a utility coin' : 'is not a utility coin'}');
          print(
              '   The total supply is ${formatAmount(token.totalSupply, token.decimals)} and the maximum supply is ${formatAmount(token.maxSupply, token.decimals)}');
        } else {
          print(
              'Token ${token.name} with symbol ${token.symbol} and standard ${magenta(token.tokenStandard.toString())}');
          print('   Issued by ${token.owner.toString()}');
          print(
              '   ${token.name} has ${token.decimals} decimals, ${token.isMintable ? 'can be minted' : 'cannot be minted'}, ${token.isBurnable ? 'can be burned' : 'cannot be burned'}, and ${token.isUtility ? 'is a utility token' : 'is not a utility token'}');
        }
        print('   Domain `${token.domain}`');
      }
      break;

    case 'token.getByStandard':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('token.getByStandard tokenStandard');
        break;
      }
      TokenStandard tokenStandard = TokenStandard.parse(args[1]);
      Token token = (await znnClient.embedded.token.getByZts(tokenStandard))!;
      String type = 'Token';
      if (token.tokenStandard.toString() == qsrTokenStandard ||
          token.tokenStandard.toString() == znnTokenStandard) {
        type = 'Coin';
      }
      print(
          '$type ${token.name} with symbol ${token.symbol} and standard ${token.tokenStandard.toString()}');
      print('   Created by ${green(token.owner.toString())}');
      print(
          '   The total supply is ${formatAmount(token.totalSupply, token.decimals)} and a maximum supply is ${formatAmount(token.maxSupply, token.decimals)}');
      print(
          '   The token has ${token.decimals} decimals ${token.isMintable ? 'can be minted' : 'cannot be minted'} and ${token.isBurnable ? 'can be burned' : 'cannot be burned'}');
      break;

    case 'token.getByOwner':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('token.getByOwner ownerAddress');
        break;
      }
      String type = 'Token';
      Address ownerAddress = Address.parse(args[1]);
      TokenList tokens =
          await znnClient.embedded.token.getByOwner(ownerAddress);
      for (Token token in tokens.list!) {
        type = 'Token';
        if (token.tokenStandard.toString() == znnTokenStandard ||
            token.tokenStandard.toString() == qsrTokenStandard) {
          type = 'Coin';
        }
        print(
            '$type ${token.name} with symbol ${token.symbol} and standard ${token.tokenStandard.toString()}');
        print('   Created by ${green(token.owner.toString())}');
        print(
            '   The total supply is ${formatAmount(token.totalSupply, token.decimals)} and a maximum supply is ${formatAmount(token.maxSupply, token.decimals)}');
        print(
            '   The token ${token.decimals} decimals ${token.isMintable ? 'can be minted' : 'cannot be minted'} and ${token.isBurnable ? 'can be burned' : 'cannot be burned'}');
      }
      break;

    case 'token.issue':
      if (args.length != 10) {
        print('Incorrect number of arguments. Expected:');
        print(
            'token.issue name symbol domain totalSupply maxSupply decimals isMintable isBurnable isUtility');
        break;
      }

      RegExp regExpName = RegExp(r'^([a-zA-Z0-9]+[-._]?)*[a-zA-Z0-9]$');
      if (!regExpName.hasMatch(args[1])) {
        print('${red("Error!")} The ZTS name contains invalid characters');
        break;
      }

      RegExp regExpSymbol = RegExp(r'^[A-Z0-9]+$');
      if (!regExpSymbol.hasMatch(args[2])) {
        print('${red("Error!")} The ZTS symbol must be all uppercase');
        break;
      }

      RegExp regExpDomain = RegExp(
          r'^([A-Za-z0-9][A-Za-z0-9-]{0,61}[A-Za-z0-9]\.)+[A-Za-z]{2,}$');
      if (args[3].isEmpty || !regExpDomain.hasMatch(args[3])) {
        print('${red("Error!")} Invalid domain');
        print('Examples of ${green('valid')} domain names:');
        print('    zenon.network');
        print('    www.zenon.network');
        print('    quasar.zenon.network');
        print('    zenon.community');
        print('Examples of ${red('invalid')} domain names:');
        print('    zenon.network/index.html');
        print('    www.zenon.network/quasar');
        break;
      }

      if (args[1].isEmpty || args[1].length > 40) {
        print(
            '${red("Error!")} Invalid ZTS name length (min 1, max 40, current ${args[1].length})');
        break;
      }

      if (args[2].isEmpty || args[2].length > 10) {
        print(
            '${red("Error!")} Invalid ZTS symbol length (min 1, max 10, current ${args[2].length})');
        break;
      }

      if (args[3].length > 128) {
        print(
            '${red("Error!")} Invalid ZTS domain length (min 0, max 128, current ${args[3].length})');
        break;
      }

      bool mintable;
      if (args[7] == '0' || args[7] == 'false') {
        mintable = false;
      } else if (args[7] == '1' || args[7] == 'true') {
        mintable = true;
      } else {
        print(
            '${red("Error!")} Mintable flag variable of type "bool" should be provided as either "true", "false", "1" or "0"');
        break;
      }

      bool burnable;
      if (args[8] == '0' || args[8] == 'false') {
        burnable = false;
      } else if (args[8] == '1' || args[8] == 'true') {
        burnable = true;
      } else {
        print(
            '${red("Error!")} Burnable flag variable of type "bool" should be provided as either "true", "false", "1" or "0"');
        break;
      }

      bool utility;
      if (args[9] == '0' || args[9] == 'false') {
        utility = false;
      } else if (args[9] == '1' || args[9] == 'true') {
        utility = true;
      } else {
        print(
            '${red("Error!")} Utility flag variable of type "bool" should be provided as either "true", "false", "1" or "0"');
        break;
      }

      int totalSupply = int.parse(args[4]);
      int maxSupply = int.parse(args[5]);
      int decimals = int.parse(args[6]);

      if (mintable == true) {
        if (maxSupply < totalSupply) {
          print(
              '${red("Error!")} Max supply must to be larger than the total supply');
          break;
        }
        if (maxSupply > (1 << 53)) {
          print(
              '${red("Error!")} Max supply must to be less than ${((1 << 53)) - 1}');
          break;
        }
      } else {
        if (maxSupply != totalSupply) {
          print(
              '${red("Error!")} Max supply must be equal to totalSupply for non-mintable tokens');
          break;
        }
        if (totalSupply == 0) {
          print(
              '${red("Error!")} Total supply cannot be "0" for non-mintable tokens');
          break;
        }
      }

      print('Issuing a new ${green('ZTS token')} will burn 1 ZNN');
      if (!confirm('Do you want to proceed?', defaultValue: false)) break;

      print('Issuing ${args[1]} ZTS token ...');
      await znnClient.send(znnClient.embedded.token.issueToken(
          args[1],
          args[2],
          args[3],
          totalSupply,
          maxSupply,
          decimals,
          mintable,
          burnable,
          utility));
      print('Done');
      break;

    case 'token.mint':
      if (args.length != 4) {
        print('Incorrect number of arguments. Expected:');
        print('token.mint tokenStandard amount receiveAddress');
        break;
      }
      TokenStandard tokenStandard = TokenStandard.parse(args[1]);
      int amount = int.parse(args[2]);
      Address mintAddress = Address.parse(args[3]);

      Token? token = await znnClient.embedded.token.getByZts(tokenStandard);
      if (token == null) {
        print('${red("Error!")} The token does not exist');
        break;
      } else if (token.isMintable == false) {
        print('${red("Error!")} The token is not mintable');
        break;
      }

      print('Minting ZTS token ...');
      await znnClient.send(znnClient.embedded.token
          .mintToken(tokenStandard, amount, mintAddress));
      print('Done');
      break;

    case 'token.burn':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('token.burn tokenStandard amount');
        break;
      }
      TokenStandard tokenStandard = TokenStandard.parse(args[1]);
      int amount = int.parse(args[2]);
      AccountInfo info =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      bool ok = true;
      for (BalanceInfoListItem entry in info.balanceInfoList!) {
        if (entry.token!.tokenStandard.toString() == tokenStandard.toString() &&
            entry.balance! < amount) {
          print(
              '${red("Error!")} You only have ${formatAmount(entry.balance!, entry.token!.decimals)} ${entry.token!.symbol} tokens');
          ok = false;
          break;
        }
      }
      if (!ok) break;
      print('Burning ${args[1]} ZTS token ...');
      await znnClient
          .send(znnClient.embedded.token.burnToken(tokenStandard, amount));
      print('Done');
      break;

    case 'token.transferOwnership':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('token.transferOwnership tokenStandard newOwnerAddress');
        break;
      }
      print('Transferring ZTS token ownership ...');
      TokenStandard tokenStandard = TokenStandard.parse(args[1]);
      Address newOwnerAddress = Address.parse(args[2]);
      var token = (await znnClient.embedded.token.getByZts(tokenStandard))!;
      if (token.owner.toString() != address!.toString()) {
        print('${red('Error!')} Not owner of token ${args[1]}');
        break;
      }
      await znnClient.send(znnClient.embedded.token.updateToken(
          tokenStandard, newOwnerAddress, token.isMintable, token.isBurnable));
      print('Done');
      break;

    case 'token.disableMint':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('token.disableMint tokenStandard');
        break;
      }
      print('Disabling ZTS token mintable flag ...');
      TokenStandard tokenStandard = TokenStandard.parse(args[1]);
      var token = (await znnClient.embedded.token.getByZts(tokenStandard))!;
      if (token.owner.toString() != address!.toString()) {
        print('${red('Error!')} Not owner of token ${args[1]}');
        break;
      }
      await znnClient.send(znnClient.embedded.token
          .updateToken(tokenStandard, token.owner, false, token.isBurnable));
      print('Done');
      break;

    case 'wallet.createNew':
      if (!(args.length == 2 || args.length == 3)) {
        print('Incorrect number of arguments. Expected:');
        print('wallet.createNew passphrase [keyStoreName]');
        break;
      }

      String? name;
      if (args.length == 3) name = args[2];

      File keyStore = await znnClient.keyStoreManager.createNew(args[1], name);
      print(
          'keyStore ${green('successfully')} created: ${path.basename(keyStore.path)}');
      break;

    case 'wallet.createFromMnemonic':
      if (!(args.length == 3 || args.length == 4)) {
        print('Incorrect number of arguments. Expected:');
        print(
            'wallet.createFromMnemonic "${green('mnemonic')}" passphrase [keyStoreName]');
        break;
      }
      if (!bip39.validateMnemonic(args[1])) {
        throw AskValidatorException(red('Invalid mnemonic'));
      }

      String? name;
      if (args.length == 4) name = args[3];
      File keyStore = await znnClient.keyStoreManager
          .createFromMnemonic(args[1], args[2], name);
      print(
          'keyStore ${green('successfully')} created from mnemonic: ${path.basename(keyStore.path)}');
      break;

    case 'wallet.dumpMnemonic':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('wallet.dumpMnemonic');
        break;
      }

      print('Mnemonic for keyStore ${znnClient.defaultKeyStorePath!}');
      print(znnClient.defaultKeyStore!.mnemonic);
      break;

    case 'wallet.export':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('wallet.export filePath');
        break;
      }

      await znnClient.defaultKeyStorePath!.copy(args[1]);
      print('Done! Check the current directory');
      break;

    case 'wallet.list':
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('wallet.list');
        break;
      }
      List<File> stores = await znnClient.keyStoreManager.listAllKeyStores();
      if (stores.isNotEmpty) {
        print('Available keyStores:');
        for (File store in stores) {
          print(path.basename(store.path));
        }
      } else {
        print('No keyStores found');
      }
      break;

    case 'wallet.deriveAddresses':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('wallet.deriveAddresses');
        break;
      }

      print('Addresses for keyStore ${znnClient.defaultKeyStorePath!}');
      int left = int.parse(args[1]);
      int right = int.parse(args[2]);
      List<Address?> addresses =
          await znnClient.defaultKeyStore!.deriveAddressesByRange(left, right);
      for (int i = 0; i < right - left; i += 1) {
        print('  ${i + left}\t${addresses[i].toString()}');
      }
      break;

    case 'spork.list':
      if (!(args.length == 1 || args.length == 3)) {
        print('Incorrect number of arguments. Expected:');
        print('spork.list [pageIndex pageSize]');
        break;
      }
      int pageIndex = 0;
      int pageSize = rpcMaxPageSize;
      if (args.length == 3) {
        pageIndex = int.parse(args[1]);
        pageSize = int.parse(args[2]);
      }

      SporkList sporks = await znnClient.embedded.spork
          .getAll(pageIndex: pageIndex, pageSize: pageSize);
      if (sporks.list.isNotEmpty) {
        print('Sporks:');
        for (Spork spork in sporks.list) {
          print('Name: ${spork.name}');
          print('  Description: ${spork.description}');
          print('  Activated: ${spork.activated}');
          if (spork.activated) {
            print('  EnforcementHeight: ${spork.enforcementHeight}');
          }
          print('  Hash: ${spork.id}');
        }
      } else {
        print('No sporks found');
      }
      break;

    case 'spork.create':
      if (args.length != 3) {
        print('Incorrect number of arguments. Expected:');
        print('spork.create name description');
        break;
      }

      String name = args[1];
      String description = args[2];

      if (name.length < sporkNameMinLength ||
          name.length > sporkNameMaxLength) {
        print(
            '${red("Error!")} Spork name must be $sporkNameMinLength to $sporkNameMaxLength characters in length');
        break;
      }
      if (description.isEmpty) {
        print('${red("Error!")} Spork description cannot be empty');
        break;
      }
      if (description.length > sporkDescriptionMaxLength) {
        print(
            '${red("Error!")} Spork description cannot exceed $sporkDescriptionMaxLength characters in length');
        break;
      }

      print('Creating spork...');
      await znnClient
          .send(znnClient.embedded.spork.createSpork(name, description));
      print('Done');
      break;

    case 'spork.activate':
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('spork.activate id');
        break;
      }

      Hash id = Hash.parse(args[1]);
      print('Activating spork...');
      await znnClient.send(znnClient.embedded.spork.activateSpork(id));
      print('Done');
      break;

    case 'createHash':
      if (args.length > 3) {
        print('Incorrect number of arguments. Expected:');
        print('createHash [hashType preimageLength]');
        break;
      }

      Hash hash;
      int hashType = 0;
      final List<int> preimage;
      int preimageLength = htlcPreimageDefaultLength;

      if (args.length >= 2) {
        try {
          hashType = int.parse(args[1]);
          if (hashType > 1) {
            print(
                '${red("Error!")} Invalid hash type. Value $hashType not supported.');
            break;
          }
        } catch (e) {
          print('${red("Error!")} hash type must be an integer.');
          print('Supported hash types:');
          print('  0: SHA3-256');
          print('  1: SHA2-256');
          break;
        }
      }

      if (args.length == 3) {
        try {
          preimageLength = int.parse(args[2]);
        } catch (e) {
          print('${red("Error!")} preimageLength must be an integer.');
          break;
        }
      }

      if (preimageLength > htlcPreimageMaxLength ||
          preimageLength < htlcPreimageMinLength) {
        print(
            '${red("Error!")} Invalid preimageLength. Preimage must be $htlcPreimageMaxLength bytes or less.');
        break;
      }
      if (preimageLength < htlcPreimageDefaultLength) {
        print(
            '${yellow("Warning!")} preimageLength is less than $htlcPreimageDefaultLength and may be insecure');
      }
      preimage = generatePreimage(preimageLength);
      print('Preimage: ${hex.encode(preimage)}');

      switch (hashType) {
        case 1:
          hash = Hash.fromBytes(await Crypto.sha256Bytes(preimage));
          print('SHA-256 Hash: $hash');
          break;
        default:
          hash = Hash.digest(preimage);
          print('SHA-3 Hash: $hash');
          break;
      }
      break;

    case 'htlc.create':
      if (args.length < 5 || args.length > 7) {
        print('Incorrect number of arguments. Expected:');
        print(
            'htlc.create hashLockedAddress tokenStandard amount expirationTime [hashType hashLock]');
        break;
      }

      Address hashLockedAddress;
      TokenStandard tokenStandard;
      int amount;
      int expirationTime;
      late Hash hashLock;
      int keyMaxSize = htlcPreimageMaxLength;
      int hashType = 0;
      late List<int> preimage;

      int htlcTimelockMinHours = 60 * 60; // 1 hour
      int htlcTimelockMaxHours = htlcTimelockMinHours * 24; // 1 day

      try {
        hashLockedAddress = Address.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} hashLockedAddress must be a valid address');
        break;
      }

      try {
        if (args[2].toLowerCase() == 'znn') {
          tokenStandard = znnZts;
        } else if (args[2].toLowerCase() == 'qsr') {
          tokenStandard = qsrZts;
        } else {
          tokenStandard = TokenStandard.parse(args[2]);
        }
      } catch (e) {
        print('${red("Error!")} tokenStandard must be a valid token standard');
        print('Examples: ${green("ZNN")}/${blue("QSR")}/${magenta("ZTS")}');
        break;
      }

      try {
        amount = (double.parse(args[3]) *
                (await znnClient.embedded.token.getByZts(tokenStandard))!
                    .decimalsExponent())
            .round();
      } catch (e) {
        print('${red("Error!")} amount is not a valid number');
        break;
      }

      if (amount <= 0) {
        print('${red("Error!")} amount must be greater than 0');
        break;
      }

      AccountInfo info =
          await znnClient.ledger.getAccountInfoByAddress(address!);
      bool ok = true;
      bool found = false;
      for (BalanceInfoListItem entry in info.balanceInfoList!) {
        if (entry.token!.tokenStandard.toString() == tokenStandard.toString()) {
          amount =
              (double.parse(args[3]) * entry.token!.decimalsExponent()).round();
          if (entry.balance! < amount) {
            print(
                '${red("Error!")} You only have ${formatAmount(entry.balance!, entry.token!.decimals)} ${entry.token!.symbol} tokens');
            ok = false;
            break;
          }
          found = true;
        }
      }

      if (!ok) break;
      if (!found) {
        print(
            '${red("Error!")} You only have ${formatAmount(0, 0)} ${tokenStandard.toString()} tokens');
        break;
      }
      Token? token = await znnClient.embedded.token.getByZts(tokenStandard);

      if (args.length >= 6) {
        try {
          hashType = int.parse(args[5]);
        } catch (e) {
          print('${red("Error!")} hash type must be an integer.');
          print('Supported hash types:');
          print('  0: SHA3-256');
          print('  1: SHA2-256');
          break;
        }
      }

      if (args.length == 7) {
        try {
          hashLock = Hash.parse(args[6]);
        } catch (e) {
          print('${red("Error!")} hashLock is not a valid hash');
          break;
        }
      } else {
        preimage = generatePreimage(htlcPreimageDefaultLength);
        switch (hashType) {
          case 1:
            hashLock = Hash.fromBytes(await Crypto.sha256Bytes(preimage));
            break;
          default:
            hashLock = Hash.digest(preimage);
            break;
        }
      }

      try {
        expirationTime = int.parse(args[4]);
      } catch (e) {
        print('${red("Error!")} expirationTime must be an integer.');
        break;
      }

      if (expirationTime < htlcTimelockMinHours ||
          expirationTime > htlcTimelockMaxHours) {
        print(
            '${red("Error!")} expirationTime (seconds) must be at least $htlcTimelockMinHours and at most $htlcTimelockMaxHours.');
        break;
      }

      final duration = Duration(seconds: expirationTime);
      format(Duration d) => d.toString().split('.').first.padLeft(8, '0');
      Momentum currentFrontierMomentum =
          await znnClient.ledger.getFrontierMomentum();
      int currentTime = currentFrontierMomentum.timestamp;
      expirationTime += currentTime;

      if (args.length == 7) {
        print(
            'Creating htlc with amount ${formatAmount(amount, token!.decimals)} ${token.symbol}');
      } else {
        print(
            'Creating htlc with amount ${formatAmount(amount, token!.decimals)} ${token.symbol} using preimage ${green(hex.encode(preimage))}');
      }
      print('  Can be reclaimed in ${format(duration)} by $address');
      print(
          '  Can be unlocked by $hashLockedAddress with hashlock $hashLock hashtype $hashType');

      AccountBlockTemplate block = await znnClient.send(znnClient.embedded.htlc
          .create(token, amount, hashLockedAddress, expirationTime, hashType,
              keyMaxSize, hashLock.getBytes()));

      print('Submitted htlc with id ${green(block.hash.toString())}');
      print('Done');
      break;

    case ('htlc.unlock'):
      if (args.length < 2 || args.length > 3) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.unlock id preimage');
        break;
      }

      Hash id;
      String preimage = '';
      late Hash preimageCheck;
      int hashType = 0;
      int currentTime =
          ((DateTime.now().millisecondsSinceEpoch) / 1000).floor();

      try {
        id = Hash.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} id is not a valid hash');
        break;
      }

      HtlcInfo htlc;
      try {
        htlc = await znnClient.embedded.htlc.getById(id);
        hashType = htlc.hashType;
      } catch (e) {
        print('${red("Error!")} The htlc id $id does not exist');
        break;
      }

      if (!await znnClient.embedded.htlc
          .getProxyUnlockStatus(htlc.hashLocked)) {
        print('${red("Error!")} Cannot unlock htlc. Permission denied');
        break;
      } else if (htlc.expirationTime <= currentTime) {
        print('${red("Error!")} Cannot unlock htlc. Time lock expired');
        break;
      }

      if (args.length == 2) {
        print('Insert preimage:');
        stdin.echoMode = false;
        preimage = stdin.readLineSync()!;
        stdin.echoMode = true;
      } else if (args.length == 3) {
        preimage = args[2];
      }

      if (preimage.isEmpty) {
        print('${red("Error!")} Cannot unlock htlc. Invalid pre-image');
        break;
      }

      switch (hashType) {
        case 1:
          print('HashType 1 detected. Encoding preimage to SHA-256...');
          preimageCheck =
              Hash.fromBytes(await Crypto.sha256Bytes(hex.decode(preimage)));
          break;
        default:
          preimageCheck = (Hash.digest(hex.decode(preimage)));
          break;
      }

      if (preimageCheck != Hash.fromBytes(htlc.hashLock)) {
        print('${red('Error!')} preimage does not match the hashlock');
        break;
      }

      await znnClient.embedded.token.getByZts(htlc.tokenStandard).then(
          (token) => print(
              'Unlocking htlc id ${htlc.id} with amount ${formatAmount(htlc.amount, token!.decimals)} ${token.symbol}'));

      await znnClient
          .send(znnClient.embedded.htlc.unlock(id, hex.decode(preimage)));
      print('Done');
      print('Use receiveAll to collect your htlc amount after 2 momentums');
      break;

    case ('htlc.reclaim'):
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.reclaim id');
        break;
      }

      Hash id;
      int currentTime =
          ((DateTime.now().millisecondsSinceEpoch) / 1000).floor();

      try {
        id = Hash.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} id is not a valid hash');
        break;
      }

      HtlcInfo htlc;
      try {
        htlc = await znnClient.embedded.htlc.getById(id);
      } catch (e) {
        print('${red("Error!")} The htlc id $id does not exist');
        break;
      }

      if (htlc.expirationTime > currentTime) {
        format(Duration d) => d.toString().split('.').first.padLeft(8, '0');
        print(
            '${red("Error!")} Cannot reclaim htlc. Try again in ${format(Duration(seconds: htlc.expirationTime - currentTime))}.');
        break;
      }

      if (htlc.timeLocked != address) {
        print('${red("Error!")} Cannot reclaim htlc. Permission denied');
        break;
      }

      await znnClient.embedded.token.getByZts(htlc.tokenStandard).then(
          (token) => print(
              'Reclaiming htlc id ${htlc.id} with amount ${formatAmount(htlc.amount, token!.decimals)} ${token.symbol}'));

      await znnClient.send(znnClient.embedded.htlc.reclaim(id));
      print('Done');
      print('Use receiveAll to collect your htlc amount after 2 momentums');
      break;

    case ('htlc.denyProxy'):
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.denyProxy');
        break;
      }

      await znnClient.send(znnClient.embedded.htlc.denyProxyUnlock()).then(
          (_) => print(
              'Htlc proxy unlocking is denied for ${address.toString()}'));

      print('Done');
      break;

    case ('htlc.allowProxy'):
      if (args.length != 1) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.allowProxy');
        break;
      }

      await znnClient.send(znnClient.embedded.htlc.allowProxyUnlock()).then(
          (_) => print(
              'Htlc proxy unlocking is allowed for ${address.toString()}'));

      print('Done');
      break;

    case ('htlc.getProxyStatus'):
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.getProxyStatus address');
        break;
      }

      try {
        address = Address.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} address is not valid');
        break;
      }

      await znnClient.embedded.htlc.getProxyUnlockStatus(address).then(
          (value) => print(
              'Htlc proxy unlocking is ${(value) ? green('allowed') : red('denied')} for ${address.toString()}'));

      print('Done');
      break;

    case ('htlc.get'):
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.get id');
        break;
      }

      Hash id;
      int currentTime =
          ((DateTime.now().millisecondsSinceEpoch) / 1000).floor();
      format(Duration d) => d.toString().split('.').first.padLeft(8, '0');

      try {
        id = Hash.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} id is not a valid hash');
        break;
      }

      HtlcInfo htlc;
      try {
        htlc = await znnClient.embedded.htlc.getById(id);
      } catch (e) {
        print('The htlc id $id does not exist');
        break;
      }

      await znnClient.embedded.token.getByZts(htlc.tokenStandard).then(
          (token) => print(
              'Htlc id ${htlc.id} with amount ${formatAmount(htlc.amount, token!.decimals)} ${token.symbol}'));
      if (htlc.expirationTime > currentTime) {
        print(
            '   Can be unlocked by ${htlc.hashLocked} with hashlock ${Hash.fromBytes(htlc.hashLock)} hashtype ${htlc.hashType}');
        print(
            '   Can be reclaimed in ${format(Duration(seconds: htlc.expirationTime - currentTime))} by ${htlc.timeLocked}');
      } else {
        print('   Can be reclaimed now by ${htlc.timeLocked}');
      }

      print('Done');
      break;

    case ('htlc.monitor'):
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.monitor id');
        break;
      }

      Hash id;
      HtlcInfo htlc;

      try {
        id = Hash.parse(args[1]);
      } catch (e) {
        print('${red("Error!")} id is not a valid hash');
        break;
      }

      try {
        htlc = await znnClient.embedded.htlc.getById(id);
      } catch (e) {
        print('The htlc id $id does not exist');
        break;
      }
      List<HtlcInfo> htlcs = [];
      htlcs.add(htlc);

      while (await monitorAsync(znnClient, address!, htlcs) != true) {
        await Future.delayed(Duration(seconds: 10));
      }
      break;

    case ('htlc.inspect'):
      if (args.length != 2) {
        print('Incorrect number of arguments. Expected:');
        print('htlc.inspect blockHash');
        break;
      }

      Hash blockHash = Hash.parse(args[1]);
      var block = await znnClient.ledger.getAccountBlockByHash(blockHash);

      if (block == null) {
        print('The account block ${blockHash.toString()} does not exist');
        break;
      }

      if (block.pairedAccountBlock == null ||
          block.blockType != BlockTypeEnum.userSend.index) {
        print('The account block was not sent by a user');
        break;
      }

      Function eq = const ListEquality().equals;
      late AbiFunction f;
      for (var entry in Definitions.htlc.entries) {
        if (eq(AbiFunction.extractSignature(entry.encodeSignature()),
            AbiFunction.extractSignature(block.data))) {
          f = AbiFunction(entry.name!, entry.inputs!);
        }
      }

      if (f.name == null) {
        print('The account block contains invalid data');
        break;
      }

      var txArgs = f.decode(block.data);
      if (f.name.toString() == 'Unlock') {
        if (txArgs.length != 2) {
          print('The account block has an invalid unlock argument length');
          break;
        }
        String preimage = hex.encode(txArgs[1]);
        print(
            'Unlock htlc: id ${cyan(txArgs[0].toString())} unlocked by ${block.address} with pre-image: ${green(preimage)}');
      } else if (f.name.toString() == 'Reclaim') {
        if (txArgs.length != 1) {
          print('The account block has an invalid reclaim argument length');
          break;
        }
        print(
            'Reclaim htlc: id ${red(txArgs[0].toString())} reclaimed by ${block.address}');
      } else if (f.name.toString() == 'Create') {
        if (txArgs.length != 5) {
          print('The account block has an invalid create argument length');
          break;
        }

        var hashLocked = txArgs[0];
        var expirationTime = txArgs[1];
        var hashLock = Hash.fromBytes(txArgs[4]);
        var amount = block.amount;
        var token = block.token;
        var hashType = txArgs[2].toString();
        var keyMaxSize = txArgs[3].toString();
        print('Create htlc: ${hashLocked.toString()} '
            '${formatAmount(amount, token!.decimals)} '
            '${token.symbol} $expirationTime '
            '$hashType '
            '$keyMaxSize '
            '${hashLock.toString()} '
            'created by ${block.address}');
      } else {
        print('The account block contains an unknown function call');
      }
      break;

    default:
      print('${red('Error!')} Unrecognized command ${red(args[0])}');
      help();
      break;
  }
  return;
}

Future<bool> monitorAsync(
    Zenon znnClient, Address address, List<HtlcInfo> htlcs) async {
  for (var htlc in htlcs) {
    print('Monitoring htlc id ${htlc.id}');
  }

  // Thread 1: append new htlc contract interactions to queue
  List<Hash> queue = [];
  znnClient.wsClient.addOnConnectionEstablishedCallback((broadcaster) async {
    print('Subscribing for htlc-contract events...');

    try {
      await znnClient.subscribe.toAllAccountBlocks();
    } catch (e) {
      print(e);
    }

    // Extract hashes for all new tx that interact with the htlc contract
    broadcaster.listen((json) async {
      if (json!['method'] == 'ledger.subscription') {
        for (var i = 0; i < json['params']['result'].length; i += 1) {
          var tx = json['params']['result'][i];
          if (tx['toAddress'] != htlcAddress.toString()) {
            continue;
          } else {
            var hash = tx['hash'];
            queue.add(Hash.parse(hash));
            print('Receiving transaction with hash ${orange(hash)}');
          }
        }
      }
    });
  });

  List<HtlcInfo> waitingToBeReclaimed = [];

  // Thread 2: if any tx in queue matches monitored htlc, remove it from queue
  for (;;) {
    if (htlcs.isEmpty && waitingToBeReclaimed.isEmpty) {
      break;
    }
    var currentTime = (DateTime.now().millisecondsSinceEpoch / 1000).round();
    List<HtlcInfo> _htlcs = htlcs.toList();

    for (var htlc in _htlcs) {
      // Reclaim any expired timeLocked htlc that is being monitored
      if (htlc.expirationTime <= currentTime) {
        print('Htlc id ${red(htlc.id.toString())} expired');

        if (htlc.timeLocked == address) {
          try {
            await znnClient.send(znnClient.embedded.htlc.reclaim(htlc.id));
            print('  Reclaiming htlc id ${red(htlc.id.toString())} now... ');
            htlcs.remove(htlc);
          } catch (e) {
            print('  Error occurred when reclaiming ${htlc.id}');
          }
        } else {
          print('  Waiting for ${htlc.timeLocked} to reclaim...');
          waitingToBeReclaimed.add(htlc);
          htlcs.remove(htlc);
        }
      }

      List<HtlcInfo> _waitingToBeReclaimed = waitingToBeReclaimed.toList();
      List<Hash> _queue = queue.toList();

      if (queue.isNotEmpty) {
        for (var hash in _queue) {
          // Identify if htlc tx are either 'Unlock' or 'Reclaim'
          var block = await znnClient.ledger.getAccountBlockByHash(hash);

          if (block?.blockType != BlockTypeEnum.userSend.index) {
            continue;
          }

          if (block?.pairedAccountBlock == null ||
              block?.pairedAccountBlock?.blockType !=
                  BlockTypeEnum.contractReceive.index) {
            continue;
          }

          if ((block?.pairedAccountBlock?.descendantBlocks)!.isEmpty) {
            continue;
          }

          Function eq = const ListEquality().equals;
          late AbiFunction f;
          for (var entry in Definitions.htlc.entries) {
            if (eq(AbiFunction.extractSignature(entry.encodeSignature()),
                AbiFunction.extractSignature((block?.data)!))) {
              f = AbiFunction(entry.name!, entry.inputs!);
            }
          }

          if (f.name == null) {
            continue;
          }

          // If 'Unlock', display its preimage
          for (var htlc in _htlcs) {
            if (f.name.toString() == 'Unlock') {
              var args = f.decode((block?.data)!);

              if (args.length != 2) {
                continue;
              }

              if (args[0].toString() != htlc.id.toString()) {
                continue;
              }

              if ((block?.pairedAccountBlock?.descendantBlocks)!.any((x) =>
                  x.blockType == BlockTypeEnum.contractSend.index &&
                  x.tokenStandard == htlc.tokenStandard &&
                  x.amount == htlc.amount)) {
                final preimage = hex.encode(args[1]);
                print(
                    'htlc id ${cyan(htlc.id.toString())} unlocked with pre-image: ${green(preimage)}');

                htlcs.remove(htlc);
              }
            }
          }

          // If 'Reclaim', inform user that a monitored, expired htlc
          // and has been reclaimed by the timeLocked address
          for (var htlc in _waitingToBeReclaimed) {
            if (f.name.toString() == 'Reclaim') {
              if (block?.address != htlc.timeLocked) {
                continue;
              }

              var args = f.decode((block?.data)!);

              if (args.length != 1) {
                continue;
              }

              if (args[0].toString() != htlc.id.toString()) {
                continue;
              }

              if ((block?.pairedAccountBlock?.descendantBlocks)!.any((x) =>
                  x.blockType == BlockTypeEnum.contractSend.index &&
                  x.toAddress == htlc.timeLocked &&
                  x.tokenStandard == htlc.tokenStandard &&
                  x.amount == htlc.amount)) {
                print(
                    'htlc id ${red(htlc.id.toString())} reclaimed by ${htlc.timeLocked}');
                waitingToBeReclaimed.remove(htlc);
              } else {
                print((block?.pairedAccountBlock?.descendantBlocks)!);
              }
            }
          }
          queue.remove(hash);
        }
      }
      await Future.delayed(Duration(seconds: 1));
    }
  }
  print('No longer monitoring the htlc');
  return true;
}

List<int> generatePreimage([int length = htlcPreimageDefaultLength]) {
  const maxInt = 256;
  return List<int>.generate(length, (i) => Random.secure().nextInt(maxInt));
}
