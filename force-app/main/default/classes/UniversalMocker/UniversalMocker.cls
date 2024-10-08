/************************************************************

*** @author: Suraj Pillai
*** @group: Test Class
*** @date: 01/2020
*** @description: A universal class for mocking in tests. Contains a method for setting the return value for any method. Another method returns the number of times a method was called. https://github.com/surajp/universalmock

*/
@IsTest
public with sharing class UniversalMocker implements System.StubProvider {
  // Map of methodName+paramTypes -> map of (paramname,value) for each invocation
  private Map<String, List<Map<String, Object>>> argumentsMap = new Map<String, List<Map<String, Object>>>();
  private final Type mockedClass;
  private Map<String, Object> mocksMap = new Map<String, Object>();
  private Map<String, List<Integer>> returnUntilMap = new Map<String, List<Integer>>();
  private Map<String, List<Integer>> mutateUntilMap = new Map<String, List<Integer>>();
  private Map<String, Integer> callCountsMap = new Map<String, Integer>();

  @TestVisible
  private static final Map<String, UniversalMocker> uMockInstances = new Map<String, UniversalMocker>();

  //even though the 'guid' we are generating is a long (using Crypto.getRandomLong), we keep this a string, to make it easier if we need to switch to an actual guid in the future, and it isn't really costing us anything
  private String guid;

  private String currentMethodName;
  private String currentParamTypesString;
  private Integer forInvocationNumber = 0;
  private Integer callCountToMock = null;

  private String KEY_DELIMITER = '||';

  //Map for storing mutators
  Map<String, List<Mutator>> mutatorMap = new Map<String, List<Mutator>>();

  // Inner class instances
  private InitialSetupState setupAInstance;
  private InitialValidationState assertAInstance;
  private IntermediateValidationState assertBInstance;
  private InitialParamValidationState getParamsAInstance;

  private enum Modes {
    SETUP,
    ASSERT,
    GETPARAMS
  }

  /* Begin Public Methods */

  public enum Times {
    OR_LESS,
    OR_MORE,
    EXACTLY
  }

  public static UniversalMocker mock(Type mockedClass) {
    UniversalMocker uMock = new UniversalMocker(mockedClass);
    uMockInstances.put(uMock.guid, uMock);
    return uMock;
  }

  public Object createStub() {
    return Test.createStub(this.mockedClass, this);
  }

  public class InitialSetupState extends FinalSetupState {
    private InitialSetupState(UniversalMocker parent) {
      super(parent);
    }
    public FinalSetupState withParamTypes(List<Type> paramTypes) {
      this.parent.withParamTypes(paramTypes);
      return (FinalSetupState) this;
    }
  }

  public virtual class FinalSetupState {
    private final UniversalMocker parent;
    private FinalSetupState(UniversalMocker parent) {
      this.parent = parent;
    }
    public FinalSetupState mutateUntil(Integer callCount, Mutator mutatorInstance) {
      this.parent.mutateUntil(callCount, mutatorInstance);
      return this;
    }
    public FinalSetupState mutateWith(Mutator mutatorInstance) {
      this.parent.mutateWith(mutatorInstance);
      return this;
    }
    public void thenReturnVoid() {
      this.parent.thenReturnVoid();
    }
    public void thenReturn(Object returnObject) {
      this.parent.thenReturn(returnObject);
    }
    public void thenThrow(Exception exceptionToThrow) {
      this.parent.thenThrow(exceptionToThrow);
    }
    public FinalSetupState thenReturnUntil(Integer callCount, Object returnObject) {
      this.parent.thenReturnUntil(callCount, returnObject);
      return this;
    }
    public FinalSetupState thenThrowUntil(Integer callCount, Exception exceptionToThrow) {
      this.parent.thenThrowUntil(callCount, exceptionToThrow);
      return this;
    }
  }

  public class InitialValidationState {
    private final UniversalMocker parent;
    private InitialValidationState(UniversalMocker parent) {
      this.parent = parent;
    }
    public IntermediateValidationState method(String methodName) {
      parent.method(methodName);
      return parent.assertBInstance;
    }
  }

  public class IntermediateValidationState extends FinalValidationState {
    private IntermediateValidationState(UniversalMocker parent) {
      super(parent);
    }
    public FinalValidationState withParamTypes(List<Type> paramTypes) {
      parent.withParamTypes(paramTypes);
      return (FinalValidationState) this;
    }
  }

  public virtual class FinalValidationState {
    private final UniversalMocker parent;
    private FinalValidationState(UniversalMocker parent) {
      this.parent = parent;
    }
    public void wasCalled(Integer expectedCallCount, Times assertTypeValue) {
      parent.wasCalled(expectedCallCount, assertTypeValue);
    }
    public void wasCalled(Integer expectedCallCount) {
      parent.wasCalled(expectedCallCount);
    }
    public void wasNeverCalled() {
      parent.wasNeverCalled();
    }
  }

  public class InitialParamValidationState extends IntermediateParamValidationState {
    private InitialParamValidationState(UniversalMocker parent) {
      super(parent);
    }
    public IntermediateParamValidationState withParamTypes(List<Type> paramTypes) {
      parent.withParamTypes(paramTypes);
      return (IntermediateParamValidationState) this;
    }
  }

  public virtual class IntermediateParamValidationState extends FinalParamValidationState {
    private IntermediateParamValidationState(UniversalMocker parent) {
      super(parent);
    }
    public FinalParamValidationState andInvocationNumber(Integer invocation) {
      parent.andInvocationNumber(invocation);
      return (FinalParamValidationState) this;
    }
  }

  public virtual class FinalParamValidationState {
    private final UniversalMocker parent;
    private FinalParamValidationState(UniversalMocker parent) {
      this.parent = parent;
    }
    public Object getValueOf(String paramName) {
      return parent.getValueOf(paramName);
    }
    public Map<String, Object> getArgumentsMap() {
      return parent.getArgumentsMap();
    }
  }

  public InitialSetupState when(String stubbedMethodName) {
    this.reset();
    this.currentMethodName = stubbedMethodName;
    return this.setupAInstance;
  }

  public Object handleMethodCall(
    Object stubbedObject,
    String stubbedMethodName,
    Type returnType, //currently unused
    List<Type> listOfParamTypes,
    List<String> listOfParamNames,
    List<Object> listOfArgs
  ) {
    String keyInUse = this.determineKeyToUseForCurrentStubbedMethod(stubbedMethodName, listOfParamTypes);
    this.incrementCallCount(keyInUse);
    this.saveArguments(listOfParamNames, listOfArgs, keyInUse);

    for (Mutator m : this.getApplicableMutators(keyInUse)) {
      m.mutate(stubbedObject, stubbedMethodName, listOfParamTypes, listOfArgs);
    }

    Object returnValue = this.getMockValue(keyInUse);
    if (returnValue instanceof Exception) {
      throw (Exception) returnValue;
    }
    this.copyState(); //for async calls, we store the current object instance in a static map so the state is preserved even after leaving the async context
    return returnValue;
  }

  public InitialValidationState assertThat() {
    this.reset();
    return this.assertAInstance;
  }

  public InitialParamValidationState forMethod(String stubbedMethodName) {
    this.reset();
    this.currentMethodName = stubbedMethodName;
    return this.getParamsAInstance;
  }

  public class InvalidOperationException extends Exception {
  }

  public interface Mutator {
    void mutate(Object stubbedObject, String stubbedMethodName, List<Type> listOfParamTypes, List<Object> listOfArgs);
  }

  public void resetState() {
    this.reset();
    this.argumentsMap = new Map<String, List<Map<String, Object>>>();
    this.mocksMap = new Map<String, Object>();
    this.returnUntilMap = new Map<String, List<Integer>>();
    this.mutateUntilMap = new Map<String, List<Integer>>();
    this.callCountsMap = new Map<String, Integer>();
    this.mutatorMap = new Map<String, List<Mutator>>();
    this.initInnerClassInstances();
  }

  /* End Public methods */

  /* Begin Private methods */

  private void withParamTypes(List<Type> paramTypes) {
    this.currentParamTypesString = this.getParamTypesString(paramTypes);
  }

  private void mutateWith(Mutator mutatorInstance) {
    String key = this.getCurrentKey();
    this.putMutatorValue(key, mutatorInstance);
    if (!this.callCountsMap.containsKey(key)) {
      this.callCountsMap.put(key, 0);
    }
    if (this.callCountToMock != null) {
      this.callCountToMock = null;
    }
  }

  private void thenReturnVoid() {
    this.thenReturn(null);
  }

  private void thenReturn(Object returnObject) {
    String key = this.getCurrentKey();
    this.putMockValue(key, returnObject);
    if (!this.callCountsMap.containsKey(key)) {
      this.callCountsMap.put(key, 0);
    }
    if (this.callCountToMock != null) {
      this.callCountToMock = null;
    }
  }

  private void mutateUntil(Integer callCount, Mutator mutatorInstance) {
    this.callCountToMock = callCount;
    this.mutateWith(mutatorInstance);
  }

  private void thenReturnUntil(Integer callCount, Object returnObject) {
    this.callCountToMock = callCount;
    this.thenReturn(returnObject);
  }

  private void thenThrowUntil(Integer callCount, Exception exceptionToThrow) {
    this.callCountToMock = callCount;
    this.thenReturn(exceptionToThrow);
  }

  private void thenThrow(Exception exceptionToThrow) {
    this.thenReturn(exceptionToThrow);
  }

  private void method(String methodName) {
    this.currentMethodName = methodName;
  }

  private void wasCalled(Integer expectedCallCount) {
    wasCalled(expectedCallCount, UniversalMocker.Times.EXACTLY);
  }

  private void wasCalled(Integer expectedCallCount, Times assertTypeValue) {
    String currentKey = this.getCurrentKey();
    //Integer actualCallCount = this.callCountsMap.get(currentKey);
    Integer actualCallCount = this.getCallCountsMapInternal().get(currentKey);
    String methodName = this.currentMethodName;
    switch on assertTypeValue {
      when OR_LESS {
        system.assert(expectedCallCount >= actualCallCount, this.getMethodCallCountAssertMessage(methodName, 'less than or equal'));
      }
      when OR_MORE {
        system.assert(expectedCallCount <= actualCallCount, this.getMethodCallCountAssertMessage(methodName, 'more than or equal'));
      }
      when else {
        system.assertEquals(expectedCallCount, actualCallCount, this.getMethodCallCountAssertMessage(methodName, 'equal'));
      }
    }
  }

  private void wasNeverCalled() {
    String currentKey = this.getCurrentKey();
    Integer actualCallCount = this.getCallCountsMapInternal().get(currentKey);
    String methodName = this.currentMethodName;
    if (actualCallCount != null) {
      Integer expectedCallCount = 0;
      System.assertEquals(expectedCallCount, actualCallCount, String.format('Method {0} was called 1 or more times', new List<String>{ methodName }));
    }
  }

  private void andInvocationNumber(Integer invocation) {
    this.forInvocationNumber = invocation;
  }

  private Object getValueOf(String paramName) {
    String theKey = this.getCurrentKey();
    Map<String, Object> paramsMap = this.getArgumentsMapInternal().get(theKey).get(this.forInvocationNumber);
    if (!paramsMap.containsKey(paramName.toLowerCase())) {
      throw new IllegalArgumentException(String.format('Param name {0} not found for the method {1}', new List<Object>{ paramName, this.currentMethodName }));
    }
    Object returnValue = paramsMap.get(paramName.toLowerCase());
    return returnValue;
  }

  private Map<String, Object> getArgumentsMap() {
    String theKey = this.getCurrentKey();
    Map<String, Object> returnValue = this.getArgumentsMapInternal().get(theKey).get(this.forInvocationNumber);
    return returnValue;
  }

  private String getCurrentKey() {
    String retVal = this.currentMethodName;
    if (!String.isEmpty(this.currentParamTypesString)) {
      retVal += KEY_DELIMITER + this.currentParamTypesString;
    }
    return retVal.toLowerCase();
  }

  private String getKey(String methodName, List<Type> paramTypes) {
    return (methodName + KEY_DELIMITER + this.getParamTypesString(paramTypes)).toLowerCase();
  }

  private Object getMockValue(String key) {
    if (this.returnUntilMap.containsKey(key)) {
      Integer callCount = this.callCountsMap.get(key);
      List<Integer> returnUntilList = this.returnUntilMap.get(key);
      returnUntilList.sort();
      for (Integer returnUntil : returnUntilList) {
        if (returnUntil >= callCount) {
          return this.mocksMap.get(key + '-' + returnUntil);
        }
      }
    }
    return this.mocksMap.get(key);
  }

  private List<Mutator> getApplicableMutators(String key) {
    if (this.mutateUntilMap.containsKey(key)) {
      Integer callCount = this.callCountsMap.get(key);
      List<Integer> mutateUntilList = this.mutateUntilMap.get(key);
      mutateUntilList.sort();
      for (Integer mutateUntil : mutateUntilList) {
        if (mutateUntil >= callCount) {
          key = key + '-' + mutateUntil;
          break;
        }
      }
    }
    if (this.mutatorMap.containsKey(key)) {
      return this.mutatorMap.get(key);
    }
    return new List<Mutator>();
  }

  private void putMutatorValue(String key, Mutator mutatorInstance) {
    if (this.callCountToMock != null) {
      if (!this.mutateUntilMap.containsKey(key)) {
        this.mutateUntilMap.put(key, new List<Integer>{});
      }
      this.mutateUntilMap.get(key).add(this.callCountToMock);
      key = key + '-' + callCountToMock;
    }
    if (!this.mutatorMap.containsKey(key)) {
      this.mutatorMap.put(key, new List<Mutator>());
    }
    this.mutatorMap.get(key).add(mutatorInstance);
  }

  private void putMockValue(String key, Object value) {
    if (this.callCountToMock != null) {
      if (!this.returnUntilMap.containsKey(key)) {
        this.returnUntilMap.put(key, new List<Integer>{});
      }
      this.returnUntilMap.get(key).add(this.callCountToMock);
      this.mocksMap.put(key + '-' + this.callCountToMock, value);
    } else {
      this.mocksMap.put(key, value);
    }
  }

  private String getParamTypesString(List<Type> paramTypes) {
    String[] classNames = new List<String>{};
    for (Type paramType : paramTypes) {
      classNames.add(paramType.getName());
    }
    return String.join(classNames, '-');
  }

  private String determineKeyToUseForCurrentStubbedMethod(String stubbedMethodName, List<Type> listOfParamTypes) {
    String keyWithParamTypes = this.getKey(stubbedMethodName, listOfParamTypes);
    return this.callCountsMap.containsKey(keyWithParamTypes) ? keyWithParamTypes : stubbedMethodName.toLowerCase();
  }

  private void incrementCallCount(String key) {
    Integer count = this.callCountsMap.containsKey(key) ? this.callCountsMap.get(key) : 0;
    this.callCountsMap.put(key, count + 1);
  }

  private void saveArguments(List<String> listOfParamNames, List<Object> listOfArgs, String key) {
    Map<String, Object> currentArgsMap = new Map<String, Object>();
    if (!this.argumentsMap.containsKey(key)) {
      this.argumentsMap.put(key, new List<Map<String, Object>>{ currentArgsMap });
    } else {
      this.argumentsMap.get(key).add(currentArgsMap);
    }

    for (Integer i = 0; i < listOfParamNames.size(); i++) {
      currentArgsMap.put(listOfParamNames[i].toLowerCase(), listOfArgs[i]);
    }
  }

  private String getMethodCallCountAssertMessage(String methodName, String comparison) {
    return String.format('Expected call count for method {0} is not {1} to the actual count', new List<String>{ methodName, comparison });
  }

  private Map<String, Integer> getCallCountsMapInternal() {
    return uMockInstances.get(this.guid).callCountsMap;
  }

  private Map<String, List<Map<String, Object>>> getArgumentsMapInternal() {
    return uMockInstances.get(this.guid).argumentsMap;
  }

  private void copyState() {
    uMockInstances.put(this.guid, this);
  }

  private UniversalMocker(Type mockedClass) {
    this.mockedClass = mockedClass;
    this.guid = this.getGUID();
    this.initInnerClassInstances();
  }

  private String getGUID() {
    String guid = Crypto.getRandomLong() + ''; // since guid generation is expensive, we "settle" for this, as it generates unique values and is performant
    return guid;
  }

  private void initInnerClassInstances() {
    this.setupAInstance = new InitialSetupState(this);
    this.assertAInstance = new InitialValidationState(this);
    this.assertBInstance = new IntermediateValidationState(this);
    this.getParamsAInstance = new InitialParamValidationState(this);
  }

  private void reset() {
    this.currentParamTypesString = '';
    this.currentMethodName = '';
    this.forInvocationNumber = 0;
  }

  /* End  Private Methods */
}