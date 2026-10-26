trigger FitnessMemberSharingTrigger on Sales_Team_Member__c (after insert, after update) {
    FitnessMemberSharingHandler.shareWithAncestors(Trigger.new);
}
