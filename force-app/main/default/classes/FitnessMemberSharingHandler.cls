public without sharing class FitnessMemberSharingHandler {
    public static void shareWithAncestors(List<Sales_Team_Member__c> members) {
        Map<Id, Id> parentById = new Map<Id, Id>();
        Set<Id> ancestorIds = new Set<Id>();
        for (Sales_Team_Member__c m : members) {
            if (m.Sponsor__c != null) {
                parentById.put(m.Id, m.Sponsor__c);
                ancestorIds.add(m.Sponsor__c);
            }
        }
        Map<Id, Sales_Team_Member__c> ancestors = new Map<Id, Sales_Team_Member__c>();
        for (Integer depth = 0; depth < 10 && !ancestorIds.isEmpty(); depth++) {
            Set<Id> unseen = new Set<Id>(ancestorIds);
            unseen.removeAll(ancestors.keySet());
            if (unseen.isEmpty()) break;
            for (Sales_Team_Member__c a : [SELECT Id, Sponsor__c, Contact__c FROM Sales_Team_Member__c WHERE Id IN :unseen]) {
                ancestors.put(a.Id, a);
                if (a.Sponsor__c != null) ancestorIds.add(a.Sponsor__c);
            }
        }
        Set<Id> contactIds = new Set<Id>();
        Map<Id, Id> childContactById = new Map<Id, Id>();
        for (Sales_Team_Member__c m : members) if (m.Contact__c != null) { contactIds.add(m.Contact__c); childContactById.put(m.Id, m.Contact__c); }
        for (Sales_Team_Member__c a : ancestors.values()) if (a.Contact__c != null) contactIds.add(a.Contact__c);
        Map<Id, List<Id>> usersByContact = new Map<Id, List<Id>>();
        if (!contactIds.isEmpty()) {
            for (User u : [SELECT Id, ContactId FROM User WHERE ContactId IN :contactIds AND IsActive=true]) {
                if (!usersByContact.containsKey(u.ContactId)) usersByContact.put(u.ContactId, new List<Id>());
                usersByContact.get(u.ContactId).add(u.Id);
            }
        }
        List<Sales_Team_Member__Share> grants = new List<Sales_Team_Member__Share>();
        Set<String> seen = new Set<String>();
        for (Id childId : childContactById.keySet()) {
            Id ownContactId = childContactById.get(childId);
            if (usersByContact.containsKey(ownContactId)) {
                for (Id userId : usersByContact.get(ownContactId)) {
                    String key = String.valueOf(childId) + ':' + String.valueOf(userId);
                    if (!seen.contains(key)) { seen.add(key); grants.add(new Sales_Team_Member__Share(ParentId=childId, UserOrGroupId=userId, AccessLevel='Read', RowCause=Schema.Sales_Team_Member__Share.RowCause.Manual)); }
                }
            }
            Id cursor = parentById.get(childId);
            Integer depth = 0;
            while (cursor != null && depth < 10 && ancestors.containsKey(cursor)) {
                Sales_Team_Member__c ancestor = ancestors.get(cursor);
                if (ancestor.Contact__c != null && usersByContact.containsKey(ancestor.Contact__c)) {
                    for (Id userId : usersByContact.get(ancestor.Contact__c)) {
                        String key = String.valueOf(childId) + ':' + String.valueOf(userId);
                        if (!seen.contains(key)) {
                            seen.add(key);
                            grants.add(new Sales_Team_Member__Share(ParentId=childId, UserOrGroupId=userId, AccessLevel='Read', RowCause=Schema.Sales_Team_Member__Share.RowCause.Manual));
                        }
                    }
                }
                cursor = ancestor.Sponsor__c;
                depth++;
            }
        }
        if (!grants.isEmpty()) Database.insert(grants, false);
    }
}
